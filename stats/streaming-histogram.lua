-- ----------------------------------------------
-- Copyright (c) 2019, CounterFlow AI, Inc. All Rights Reserved.
-- author: Andrew Fast <af@counterflowai.com>
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE.txt file.
-- ---------------------------------------------

-- Online histogram computation algorithm from
-- Ben-Haim and Tom-Tov, “A Streaming Parallel Decision Tree Algorithm.”
-- Journal of Machine Learning Research 11 (2010) 849-872

require 'math'

function histogram_update(conn, hist_key, point, num_bins)
    dragonfly.output_event("debug", "***** update: " .. point .. " " .. num_bins .. " *****")
    
    histogram, length = get_hist_from_redis(conn, hist_key)

    -- Check that histogram contains anything
    point_str = tostring(point)
    if histogram[point_str] then
        histogram[point_str] = histogram[point_str] + 1
        table_to_redis_hash(conn, hist_key, histogram)
        return histogram
    end
    
    -- If the histogram is not "full", just add a new bin
    if length < num_bins then 
        histogram[point_str] = 1
        table_to_redis_hash(conn, hist_key, histogram)
        return histogram
    end

    histogram[point_str] = 1
    minDistance = math.huge
    minList = {}
    prevIndex = -1

    keyList = {}
    for bin, count in pairs(histogram) do 
        if count then
            table.insert(keyList, tonumber(bin))
        end
    end
    table.sort(keyList)

    for index,bin in ipairs(keyList) do 
        dragonfly.output_event("debug", "***** sorted array *****")
        dragonfly.output_event("debug", index .. ": " .. bin)

        if prevIndex >= 0 then
            distance = bin - keyList[prevIndex]
            if distance <= minDistance then
                if distance < minDistance then
                    minList = {}
                end
                minDistance = distance
                table.insert(minList, prevIndex) 
            end
        end
        prevIndex = index  
    end
    minIndex = minList[math.random(#minList)] --choose one at random

    q1 = keyList[minIndex]
    q2 = keyList[minIndex+1]

    k1 = histogram[tostring(q1)]
    k2 = histogram[tostring(q2)]

    histogram[tostring(q1)] = nil
    histogram[tostring(q2)] = nil
    
    dragonfly.output_event("debug", q1 .. ": " .. k1)
    dragonfly.output_event("debug", q2 .. ": " .. k2)

    newP = ((q1 * k1) + (q2 * k2)) / (k1 + k2)
    newValue = k1 + k2
    histogram[newP] = newValue
    table_to_redis_hash(conn, hist_key, histogram)
    return histogram
end

function histogram_density(conn, hist_key, point)
    histogram, length, minValue, maxValue = get_hist_from_redis(conn, hist_key)
    dragonfly.output_event("debug", "***** Density point: " .. point .. " min: " .. minValue .. " max: " .. maxValue)
    -- Contains the point directly
    if histogram[tostring(point)] then
        return histogram[tostring(point)]
    end

    if point < minValue or point > maxValue then
        return 0 -- Assume no support outside of the range
    end

    lowKey = -1
    highKey = -1

    prevKey = -1

    keyList = {}
    for bin, count in pairs(histogram) do 
        if count then
            table.insert(keyList, tonumber(bin))
        end
    end
    table.sort(keyList)
    dragonfly.output_event("debug", keyList)

    for index,bin in ipairs(keyList) do 
        if tonumber(bin) > point then
            highKey = bin
            lowKey = prevKey
            break
        end
        prevKey = bin
    end
    dragonfly.output_event("debug","\tLow: " .. lowKey .. " , High: " .. highKey)

    lowCount = histogram[tostring(lowKey)]
    highCount = histogram[tostring(highKey)]

    dragonfly.output_event("debug","\tLow: (" .. lowKey .. "," .. lowCount .. ")" )
    dragonfly.output_event("debug","\tHigh: (" .. highKey .. "," .. highCount .. ")" )

    slope = (highCount - lowCount) * 1.0 /(highKey - lowKey)
    proportion = (tonumber(point) - tonumber(lowKey))
    d = lowCount + (slope * proportion)

    -- print("\tslope=" + str(slope))
    -- print("\tprop=" + str(proportion))
    -- print("\tdensity=" + str(d))
    return d
end

function get_hist_from_redis(conn, key)
    command = "HGETALL " .. key
    raw_result = conn:command_line(command)

    histogram = {}
    last_value = -1
    minValue = math.huge
    maxValue = -math.huge
    length = 0
    for k,v in pairs(raw_result) do 
        if k % 2 == 0 then
            bin = tonumber(last_value)
            histogram[last_value] = tonumber(v)
            length = length + 1
            if bin < minValue then
                minValue = bin
            end
            if bin > maxValue then
                maxValue = bin
            end
        end
        last_value = v
    end
    return histogram, length, minValue, maxValue
end

function table_to_redis_hash(conn, key, table) 
    -- put table into redis as a hash
    command = "HMSET " .. key
    for point, count in pairs(table) do
        command = command .. " " .. point .. " " .. count
    end
    dragonfly.output_event("debug", command)
    -- DEL hash
    conn:command("DEL", key)
    -- HMSET
    reply = conn:command_line(command)
    if type(reply) == 'table' and reply.name ~= 'OK' then
        dragonfly.output_event("debug", command ..' : '.. reply.name)
    end
    return reply
end

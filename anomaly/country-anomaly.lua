-- ----------------------------------------------
-- Copyright(c) 2018, CounterFlow AI, Inc. All Rights Reserved.
-- author: Collins Huff <ch@counterflowai.com>
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE.txt file.
-- ----------------------------------------------

-- Country Anomaly computes an anomaly score based on country code

require 'analyzer/utils'

local redis_key = "country"
local analyzer_name = 'Country Anomaly'

function setup()
    conn = hiredis.connect()
    if conn:command('PING') ~= hiredis.status.PONG then
        dragonfly.log_event(analyzer_name..': Could not connect to redis')
        dragonfly.log_event(analyzer_name..': exiting')
        os.exit()
    end
    starttime = 0 --mle.epoch()
    print('>>>>>>>> '..analyzer_name..' starting')
    dragonfly.log_event('>>>>>>>> '..analyzer_name..' starting')
    local start = os.clock()

    -- https://datahub.io/core/country-list#resource-data<Paste>
    local filepath = "analyzer/country-codes.txt"
    local file, err = io.open(filepath,'rb')
    if file then
        while true do
            line = file:read()
            if line == nil then
                break
            elseif line ~='' then 
                local cmd = 'HMSET '..redis_key..' '..line..' '..0
                reply = conn:command_line(cmd)
                if type(reply) == 'table' and reply.name ~= 'OK' then
                    dragonfly.log_event('Country Anomaly: '..cmd..' : '..reply.name)
                end 
            end
        end
        file:close()
    end
    local cmd = 'HMSET ' .. redis_key .. ' total ' .. 0 
    reply = conn:command_line(cmd)
    if type(reply) == 'table' and reply.name ~= 'OK' then
        dragonfly.log_event('Country Anomaly: '..cmd..' : '..reply.name)
    end 
    local now = os.clock()
    local delta = now - start
    print ('>>>>>>>> Loaded Country Codes in '..delta..' seconds')
    dragonfly.log_event('>>>>>>>> Loaded Country Codes in '..delta..' seconds')
end


function loop(msg)
    local start = os.clock()
    local eve = msg
	local fields = {"analytics.ip_geo.location.country_code",}
    if not check_fields(eve, fields) then
        dragonfly.log_event(analyzer_name..': Required fields missing')
        dragonfly.analyze_event(default_analyzer, msg)
        return
    end

	local country_code = eve.analytics.ip_geo.location.country_code
    local cmd = 'HMGET '..redis_key..' total '..country_code
    local reply = conn:command_line(cmd)
    for _,v in ipairs(reply) do
        if type(v) == 'table' and v.name ~= 'OK' then
            dragonfly.log_event(analyzer_name..': '..cmd..': '..v.name)
            dragonfly.analyze_event(default_analyzer, msg) 
            return
        end 
    end

    local total = reply[1]
    local count = reply[2]

    if not tonumber(total) or not tonumber(count) then
        dragonfly.log_event(analyzer_name..': Could not convert total '.. total..' or count to number '..count)
		dragonfly.analyze_event(default_analyzer, msg)
        return
    end

    prob = tonumber(count) * 1.0 / (tonumber(total) + 1)
    inv_prob = 1 - prob

    new_total = tonumber(total) + 1
    new_count = tonumber(count) + 1

    local cmd = 'HMSET '..redis_key..' total '..new_total..' '..country_code..' '..new_count
    reply = conn:command_line(cmd)
    if type(reply) == 'table' and reply.name ~= 'OK' then
        dragonfly.log_event(analyzer_name..': '..cmd..' '..reply.name)
    end 

    analytics = eve.analytics
    if not analytics then
        analytics = {}
    end
    
    country_info = {}
    country_info["country_code"] = country_code
    country_info["score"] = inv_prob
    country_info["count"] = count
    country_info["total"] = total
    country_info["threshold"] = 0.995983936
    analytics["country"] = country_info
    eve['analytics'] = analytics
    dragonfly.analyze_event(default_analyzer, eve) 
    local now = os.clock()
    local delta = now - start
    dragonfly.log_event(analyzer_name..': time: '..delta)
end

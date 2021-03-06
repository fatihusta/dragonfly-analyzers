-- ----------------------------------------------
-- Copyright (c) 2019, CounterFlow AI, Inc. All Rights Reserved.
-- Author: Andrew Fast <af@counterflowai.com>
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE.txt file.
-- ----------------------------------------------

function setup()
	print ("Signature Test filter running")
end

function loop(msg)
    local eve = msg
    if eve then
        dragonfly.analyze_event(default_analyzer, msg)
    end
end

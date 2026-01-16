local socket = require 'socket'

local helpers = {drop_timer = 0}

local last_time = socket.gettime()

function helpers.get_delta_time()
    local current_time = socket.gettime()
    local delta_time = current_time - last_time
    last_time = current_time
    return delta_time
end

return helpers
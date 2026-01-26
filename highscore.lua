local t = {}

local filename = "highscore.txt"
local highscore = 0

function t.get_highscore()
    local f = io.open(filename, "r")

    if f then
        highscore = tonumber(f:read("*l")) or 0
        f:close()
    end

    return highscore
end

function t.set_highscore(newScore)
    if newScore > highscore then
        local f = io.open(filename, "w")
        if not f then return end
        f:write(newScore)
        f:close()
    end
end

return t
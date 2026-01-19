local t = {
    {true, true, true},
    {true, true, true},
    {false, false, false}
}

local rows = #t
local cols = #t[1]

for i = 1, rows, 1 do
    local v = true

    for j = 1, cols, 1 do
        if t[i][j] == false then
            v = false
        end    
    end

    if v then
        print("hello")
    end
end
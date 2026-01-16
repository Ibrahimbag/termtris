local blocks = require 'blocks'

local current_block = blocks[2]

local rotated_block = {}
local rows = #current_block
local cols = #current_block[1]

for j = 1, cols do
    rotated_block[j] = {}
    for i = rows, 1, -1 do
        rotated_block[j][rows - i + 1] = current_block[i][j]
    end
end

for i = 1, #rotated_block do
    for j = 1, #rotated_block[i] do
        io.write((rotated_block[i][j] and "#" or " "))
    end
    print()
end
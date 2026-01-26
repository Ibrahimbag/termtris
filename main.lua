local curses = require 'curses'
local socket = require 'socket'
local blocks = require 'blocks'
local helpers = require 'helpers'
local highscore_t = require 'highscore'

local WIN_Y, WIN_X = 0, 0
local BOARD_Y, BOARD_X = 20, 10

local function init_curses()
    local stdscr = curses.initscr()
    WIN_Y, WIN_X = stdscr:getmaxyx()
    
    curses.echo(false)
    curses.cbreak()

    local start_y = math.floor(WIN_Y / 2 - (BOARD_Y + 2) / 2)
    local start_x = math.floor(WIN_X / 2 - (BOARD_X * 2 + 2) / 2)

    local board_win = curses.newwin(BOARD_Y + 2, BOARD_X * 2 + 2, start_y, start_x) -- 2 extra space for box; doubled visual width
    board_win:keypad(true)
    board_win:nodelay(true)

    local stats_win = curses.newwin(9, start_x, start_y, 0)

    local next_win = curses.newwin(9, start_x, start_y, start_x + (BOARD_X * 2 + 2))

    local help_win = curses.newwin(11, start_x, start_y + 9, start_x + (BOARD_X * 2 + 2))

    return board_win, stats_win, next_win, help_win
end

local function init_color()
    if not curses.has_colors() then
        return false
    end

    curses.start_color()
    curses.use_default_colors()

    curses.init_pair(1, -1, 6)
    curses.init_pair(2, -1, 4)
    curses.init_pair(3, -1, 3)
    curses.init_pair(4, -1, 7)
    curses.init_pair(5, -1, 2)
    curses.init_pair(6, -1, 5)
    curses.init_pair(7, -1, 1)

    return true
end

local function init_board(board, board_colors)
    for i = 1, BOARD_Y do
        board[i] = {}
        board_colors[i] = {}

        for j = 1, BOARD_X do
            board[i][j] = false
            board_colors[i][j] = 0
        end
    end
end

local function draw_help_win(help_win)

    local _, width = help_win:getmaxyx()
    local center_x = math.floor(width / 2) 

    help_win:mvaddstr(1, 5, "← → Move")
    help_win:mvaddstr(3, 5, "↑ Rotate")
    help_win:mvaddstr(5, 5, "↓ Soft drop")
    help_win:mvaddstr(7, 5, "Z Hard drop")
    help_win:mvaddstr(9, 5, "Q Quit game")
    help_win:refresh()
end

local function check_for_exit(key, board)
    if key == 81 or key == 113 then -- Q or q key
        return true
    end

    for _, value in pairs(board[1]) do
        if value then
            return true
        end
    end

    return false
end

local function get_new_block()
    local current_block_index = math.random(1, #blocks)
    return blocks[current_block_index], current_block_index
end

local function check_wall_collision(block, cursor_position)
    local y, x = cursor_position.y, cursor_position.x

    local rows = #block
    local cols = #block[1]

    -- Get length of the longest row
    local max_length = 0
    local temp = 0

    for i = 1, rows, 1 do
        for j = 1, cols do
            if block[i][j] then
                temp = temp + 1
            elseif temp == 0 and block[i][j] == false then
                temp = temp + 1
            end
        end

        if temp > max_length then
            max_length = temp
        end

        temp = 0
    end

    -- If block is colliding with walls
    if x < 1 or x + max_length - 1 > BOARD_X then
        return true, max_length
    end

    return false, max_length
end

local function check_block_collision(block, cursor_position, board)
    local y, x = cursor_position.y, cursor_position.x

    local rows = #block
    local cols = #block[1]

    -- If block collides with bottom of the board
    if y + rows > BOARD_Y + 1 then
        return true
    end
    
    -- If block collides with another block in the board 
    for i = 1, rows do
        for j = 1, cols do
            local isBlock = block[i][j] and true or false

            if isBlock then
                local val = board[y + i - 1][x + j - 1]
                if val then
                    return true
                end
            end
        end
    end

    return false
end

local function get_fall_delay(level)
    local base = 0.5       -- seconds at level 0
    local factor = 0.9     -- 10% faster per level
    local min = 0.05       -- cap speed

    local delay = base * (factor ^ level)
    return math.max(delay, min)
end

local function move_cursor(cursor_position, block, board, key, level)
    -- Hard drop
    if key == 90 or key == 122 then -- z or Z
        local candidate_y = cursor_position.y

        -- Move down until the block would collide if moved further
        while not check_block_collision(block, {y = candidate_y + 1, x = cursor_position.x}, board) do
            candidate_y = candidate_y + 1
        end

        cursor_position.y = candidate_y

        -- Trigger immediate placement next loop
        helpers.place_timer = 0.61

        return
    end

    local gravity_delay = get_fall_delay(level)

    -- Less cooldown if soft drop
    local cooldown = key == curses.KEY_DOWN and 0.05 or gravity_delay

    if helpers.drop_timer > cooldown then
        cursor_position.y = cursor_position.y + 1
        helpers.drop_timer = 0
    end

    if key == curses.KEY_LEFT then
        cursor_position.x = cursor_position.x - 1
    elseif key == curses.KEY_RIGHT then
        cursor_position.x = cursor_position.x + 1
    end
end

local function rotate_block(current_block)
    local rotated_block = {}
    local rows = #current_block
    local cols = #current_block[1]

    for j = 1, cols do
        rotated_block[j] = {}
        for i = rows, 1, -1 do
            rotated_block[j][rows - i + 1] = current_block[i][j]
        end
    end
    
    return rotated_block
end

-- Try to rotate block and apply simple wall-kick offsets.
-- Returns rotated_block and a new cursor_position if successful, else nil.
local function try_rotate_and_kick(block, cursor_position, board)
    local rotated = rotate_block(block)

    -- Horizontal kick offsets to try (SRS-like simple approach).
    local offsets = {0, -1, 1, -2, 2}

    for _, off in ipairs(offsets) do
        local candidate_pos = {y = cursor_position.y, x = cursor_position.x + off}

        local wall, _ = check_wall_collision(rotated, candidate_pos)
        -- check_wall_collision returns (bool, max_length); use the boolean result
        if not wall then
            if not check_block_collision(rotated, candidate_pos, board) then
                return rotated, candidate_pos
            end
        end
    end

    return nil, nil
end

local function draw_current_block(current_block, cursor_position, board_win)
    local y, x = cursor_position.y, cursor_position.x
    local block = current_block.block
    local color_index = current_block.index

    local function map_x(logical_x)
        return (logical_x - 1) * 2 + 1
    end

    for i = 1, #block do
        for j = 1, #block[i] do
            local isBlock = block[i][j] and true or false
            local logical_col = x + j - 1
            local sx = map_x(logical_col)

            if isBlock then
                board_win:attron(curses.color_pair(color_index))
                board_win:mvaddstr(y + i - 1, sx, "  ")
                board_win:attroff(curses.color_pair(color_index))
            end
        end
    end
end

local function draw_board(board, board_colors, board_win)
    board_win:box(0, 0)

    local function map_x(logical_x)
        return (logical_x - 1) * 2 + 1
    end

    for i = 1, BOARD_Y do
        for j = 1, BOARD_X do
            if board[i][j] then
                board_win:attron(curses.color_pair(board_colors[i][j]))
                board_win:mvaddstr(i, map_x(j), "  ")
                board_win:attroff(curses.color_pair(board_colors[i][j]))
            end
        end
    end
end

local function place_block(current_block, board, board_colors, cursor_position)
    local y, x = cursor_position.y, cursor_position.x

    local block = current_block.block
    local color_index = current_block.index

    for i = 1, #block do
        for j = 1, #block[i] do
            if block[i][j] then
                board[y + i - 1][x + j - 1] = true
                board_colors[y + i - 1][x + j - 1] = color_index
            end
        end
    end
end

local function clear_lines(board, board_colors)
    local rows = #board
    local cols = #board[1]

    local lines_cleared = 0

    for i = 1, rows, 1 do
        local line_full = true

        for j = 1, cols, 1 do
            if board[i][j] == false then
                line_full = false
                break
            end
        end

        if line_full then
            for j = 1, cols do
                board[i][j] = false
                board_colors[i][j] = 0
            end

            for k = i, 2, -1 do
                for l = 1, cols do
                    board[k][l] = board[k - 1][l]
                    board_colors[k][l] = board_colors[k -1][l]
                end
            end

            lines_cleared = lines_cleared + 1
        end
    end

    return lines_cleared
end

local function calculate_points(lines_cleared, level)
    if lines_cleared == 0 then
        return 0
    end

    local base_points = {100, 300, 500, 800}

    local base_point = base_points[lines_cleared]

    local points = base_point * (level + 1)

    return points
end

local function draw_stats(stats_win, highscore, points, lines_cleared, level)
    stats_win:mvaddstr(2, 1, "Highscore: " .. highscore)
    stats_win:mvaddstr(4, 1, "Points: " .. points)
    stats_win:mvaddstr(6, 1, "Lines: " .. lines_cleared)
    stats_win:mvaddstr(8, 1, "Level: " .. level)
end

local function draw_next(next_win, next_block, next_block_index)
    local rows = #next_block
    local cols = #next_block[1]

    local function map_x(logical_x)
        return (logical_x - 1) * 2 + 1
    end

    for i = 1, rows do
        for j = 1, cols do
            if next_block[i][j] then
                local logical_col = 5 + j - 1
                local sx = map_x(logical_col)
                next_win:attron(curses.color_pair(next_block_index))
                next_win:mvaddstr(i + 3, sx, "  ")
                next_win:attroff(curses.color_pair(next_block_index))
            end
        end
    end
end

local function game_loop(board, board_colors, board_win, stats_win, next_win, help_win)
    local new_block = true
    local current_block = {block = {}, index = -1}
    local next_block = get_new_block()
    local next_block_index = 1
    local rotated_block = {}
    local cursor_position = {y = 1, x = BOARD_X / 2}
    local lines_cleared = 0
    local points = 0
    local highscore = highscore_t.get_highscore()
    local level = 0

    draw_help_win(help_win)

    repeat
        board_win:clear()
        stats_win:clear()
        next_win:clear()

        local delta_time = helpers.get_delta_time()
        helpers.drop_timer = helpers.drop_timer + delta_time

        if new_block then
            current_block.block = next_block
            current_block.index = next_block_index
            next_block, next_block_index = get_new_block()
            new_block = false
        end

        local key = board_win:getch()

        local temp_y, temp_x = cursor_position.y, cursor_position.x

        move_cursor(cursor_position, current_block.block, board, key, level)

        if key == curses.KEY_UP then
            local rotated, new_pos = try_rotate_and_kick(current_block.block, cursor_position, board)

            if rotated and new_pos then
                current_block.block = rotated
                cursor_position.x = new_pos.x
                cursor_position.y = new_pos.y
                rotated_block = rotated
            else
                rotated_block = nil
            end
        else
            rotated_block = nil
        end

        local block_collided = check_wall_collision(current_block.block, cursor_position)

        if block_collided and rotated_block == nil then
            cursor_position.x = temp_x
        end

        block_collided = check_block_collision(current_block.block, cursor_position, board)

        if block_collided then
            helpers.place_timer = helpers.place_timer + delta_time
            cursor_position.y, cursor_position.x = temp_y, temp_x
        end

        local lines_cleared_temp = clear_lines(board, board_colors)

        points = points + calculate_points(lines_cleared_temp, level)

        lines_cleared = lines_cleared + lines_cleared_temp

        level = math.floor(lines_cleared / 10)

        if points > highscore then
            highscore = points
        end

        draw_current_block(current_block, cursor_position, board_win)

        draw_board(board, board_colors, board_win)

        draw_stats(stats_win, highscore, points, lines_cleared, level)

        draw_next(next_win, next_block, next_block_index)

        if helpers.place_timer > 0.6 then
            place_block(current_block, board, board_colors, cursor_position)
            new_block = true
            cursor_position.y = 1
            cursor_position.x = BOARD_X / 2
            helpers.place_timer = 0
        end

        board_win:refresh()
        stats_win:refresh()
        next_win:refresh()

        socket.sleep(0.07)
    until check_for_exit(key, board)

    highscore_t.set_highscore(highscore)

    help_win:clear()
end

local function main()
    os.setlocale("", "all")

    local success, board_win, stats_win, next_win, help_win = pcall(init_curses)

    if not success then
        curses.endwin()
        print("Failed to initialize curses. Try increasing your terminal resolution.")
        return
    end

    init_color()

    math.randomseed(os.time())

    local board = {}
    local board_colors = {}

    init_board(board, board_colors)

    game_loop(board, board_colors, board_win, stats_win, next_win, help_win)

    curses.endwin()
end

main()
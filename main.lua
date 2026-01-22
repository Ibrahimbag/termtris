local curses = require 'curses'
local socket = require 'socket'
local blocks = require 'blocks'
local helpers = require 'helpers'

local WIN_Y, WIN_X = 0, 0
local BOARD_Y, BOARD_X = 20, 10

local function init_board(board)
    for i = 1, BOARD_Y do
        board[i] = {}
        for j = 1, BOARD_X do
            board[i][j] = false
        end
    end
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

local function get_new_block(new_block)
    local current_block_index = math.random(1, #blocks)
    new_block.val = false
    return blocks[current_block_index]
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

local function move_cursor(cursor_position, block, board, key)
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

    -- Less cooldown if soft drop
    local cooldown = key == curses.KEY_DOWN and 0.1 or 0.3

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

local function draw_current_block(current_block, cursor_position, board_win)
    local y, x = cursor_position.y, cursor_position.x

    local function map_x(logical_x)
        return (logical_x - 1) * 2 + 1
    end

    for i = 1, #current_block do
        for j = 1, #current_block[i] do
            local isBlock = current_block[i][j] and true or false
            local logical_col = x + j - 1
            local sx = map_x(logical_col)

            if isBlock then
                board_win:mvaddstr(y + i - 1, sx, "##")
            else
                board_win:mvaddstr(y + i - 1, sx, "  ")
            end
        end
    end
end

local function draw_board(board, board_win)
    board_win:box(0, 0)
    local function map_x(logical_x)
        return (logical_x - 1) * 2 + 1
    end

    for i = 1, BOARD_Y do
        for j = 1, BOARD_X do
            if board[i][j] then
                board_win:mvaddstr(i, map_x(j), "##")
            end
        end
    end
end

local function place_block(block, board, cursor_position)
    local y, x = cursor_position.y, cursor_position.x

    for i = 1, #block do
        for j = 1, #block[i] do
            if block[i][j] then
                board[y + i - 1][x + j - 1] = true
            end
        end
    end
end

local function clear_lines(board)
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
            end

            for k = i, 2, -1 do
                for l = 1, cols do
                    board[k][l] = board[k - 1][l]
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

local function game_loop(board, board_win)
    local new_block = {val = true}
    local current_block = {}
    local rotated_block = {}
    local cursor_position = {y = 1, x = BOARD_X / 2}
    local lines_cleared = 0
    local points = 0
    local level = 0

   repeat
        board_win:clear()

        local delta_time = helpers.get_delta_time()
        helpers.drop_timer = helpers.drop_timer + delta_time

        if new_block.val then
            current_block = get_new_block(new_block)
        end

        local key = board_win:getch()

        local temp_y, temp_x = cursor_position.y, cursor_position.x

        move_cursor(cursor_position, current_block, board, key)

        if key == curses.KEY_UP then
            rotated_block = rotate_block(current_block)

            local ret1, max_length = check_wall_collision(rotated_block, cursor_position)
            local ret2 = check_block_collision(rotated_block, cursor_position, board)

            if ret1 then
                cursor_position.x = temp_x - max_length + 1
            end

            if not ret2 then
                current_block = rotated_block -- This is temporary. change it later with a better algorithm
            end
        else
            rotated_block = nil
        end

        local block_collided = check_wall_collision(current_block, cursor_position)

        if block_collided and rotated_block == nil then
            cursor_position.x = temp_x
        end

        block_collided = check_block_collision(current_block, cursor_position, board)

        if block_collided then
            helpers.place_timer = helpers.place_timer + delta_time
            cursor_position.y, cursor_position.x = temp_y, temp_x
        end

        if helpers.place_timer > 0.6 then
            place_block(current_block, board, cursor_position)
            current_block = get_new_block(new_block)
            cursor_position.y = 1
            cursor_position.x = BOARD_X / 2
            helpers.place_timer = 0
        end

        local lines_cleared_temp = clear_lines(board)

        points = points + calculate_points(lines_cleared_temp, level) -- keep level at 0 for now

        lines_cleared = lines_cleared + lines_cleared_temp

        level = math.floor(lines_cleared / 10)

        draw_current_block(current_block, cursor_position, board_win)

        draw_board(board, board_win)

        -- DEBUG
        board_win:mvaddstr(1, 1, points)
        board_win:mvaddstr(1, 9, lines_cleared)
        board_win:mvaddstr(1, 17, level)

        board_win:refresh()

        socket.sleep(0.07)
   until check_for_exit(key, board)
end

local function main()
    local stdscr = curses.initscr()
    WIN_Y, WIN_X = stdscr:getmaxyx()
    curses.echo(false)
    curses.cbreak()

    local board_win = curses.newwin(BOARD_Y + 2, BOARD_X * 2 + 2, 0, 0) -- 2 extra space for box; doubled visual width
    board_win:keypad(true)
    board_win:nodelay(true)

    math.randomseed(os.time())

    local board = {}

    init_board(board)

    game_loop(board, board_win)

    curses.endwin()
end

main()
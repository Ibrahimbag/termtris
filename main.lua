local curses = require 'curses'
local socket = require 'socket'
local blocks = require 'blocks'
local helpers = require 'helpers'

local WIN_Y, WIN_X = 0, 0
local BOARD_Y, BOARD_X = 20, 20

local function init_board(board)
    for i = 1, BOARD_Y do
        board[i] = {}
        for j = 1, BOARD_X do
            board[i][j] = false
        end
    end
end

local function check_for_exit(key)
    if key == 81 or key == 113 then -- Q or q key
        return true
    end

    return false
end

local function get_new_block(new_block)
    local current_block_index = math.random(1, #blocks)
    new_block.val = false
    return blocks[current_block_index]
end

-- TODO: Probably have to divide this function into two functions later on
local function check_wall_collision(block, cursor_position, board)
    local y, x = cursor_position.y, cursor_position.x

    local rows = #block
    local cols = #block[1]

    -- Get length of the longest row
    max_length = 0
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
    if x < 1 or x + max_length > BOARD_Y then
        return true
    end
end

local function check_block_collision(block, cursor_position, board)
    local y, x = cursor_position.y, cursor_position.x

    local rows = #block
    local cols = #block[1]

    -- If block collides with bottom of the board
    if y + rows > BOARD_Y then
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

local function move_cursor(cursor_position, key)
    if helpers.drop_timer > 0.3 then
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

    for i = 1, #current_block do
        for j = 1, #current_block[i] do
            local isBlock = current_block[i][j] and true or false

            if isBlock then
                board_win:mvaddstr(y + i - 1, x + j - 1, "#")
            else
                board_win:mvaddstr(y + i - 1, x + j - 1, " ")
            end
        end
    end
end

local function draw_board(board, board_win)
    board_win:box(0, 0)
    for i = 1, BOARD_Y do
        for j = 1, BOARD_X do
            if board[i][j] then
                board_win:mvaddch(i, j, "#")
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

local function game_loop(board, board_win)
    local new_block = {val = true}
    local current_block = {}
    local cursor_position = {y = 1, x = BOARD_X / 2}

   repeat
        board_win:clear()

        local delta_time = helpers.get_delta_time()
        helpers.drop_timer = helpers.drop_timer + delta_time

        if new_block.val then
            current_block = get_new_block(new_block)
        end

        local key = board_win:getch()

        local temp_y, temp_x = cursor_position.y, cursor_position.x

        move_cursor(cursor_position, key)

        if check_wall_collision(current_block, cursor_position, board) then
            cursor_position.x = temp_x
        end
        board_win:mvaddstr(1, 1, max_length)

        if key == curses.KEY_UP then
            current_block = rotate_block(current_block)
        end

        local block_collided = check_block_collision(current_block, cursor_position, board)

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

        draw_current_block(current_block, cursor_position, board_win)

        draw_board(board, board_win)

        board_win:refresh()

        socket.sleep(0.07)
   until check_for_exit(key)
end

local function main()
    local stdscr = curses.initscr()
    WIN_Y, WIN_X = stdscr:getmaxyx()
    curses.echo(false)
    curses.cbreak()

    local board_win = curses.newwin(BOARD_Y + 1, BOARD_X + 1, 0, 0) -- 1 extra space for box
    board_win:keypad(true)
    board_win:nodelay(true)

    math.randomseed(os.time())

    local board = {}

    init_board(board)

    game_loop(board, board_win)

    curses.endwin()
end

main()
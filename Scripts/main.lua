local util = require("util")
local settings = require("settings")
local hud = require("hud")
local menu = require("menu")
local theme = require("theme")

local TICK_INTERVAL = 0.05

settings.load()
theme.start()

local lastTick = os.clock()

local function update()
    local now = os.clock()
    if menu.isOpen() then
        local ok, err = pcall(menu.frame, now)
        if not ok then
            util.warnOnce("frame:" .. tostring(err), "Error in the settings window: " .. tostring(err))
            menu.abandon()
        end
    end
    if now - lastTick >= TICK_INTERVAL then
        hud.tick(now, now - lastTick)
        theme.tick(now)
        menu.tick(now)
        settings.update(now)
        lastTick = now
    end
end

-- Runs every frame on the game thread. LoopAsync would run on a second thread, and Lua must never run on
-- two threads at once: that corrupts its state and crashes the game.
LoopInGameThreadAfterFrames(1, function()
    local ok, err = pcall(update)
    if not ok then
        util.warnOnce("update:" .. tostring(err), "Error while updating the HUD: " .. tostring(err))
    end
    return false
end)

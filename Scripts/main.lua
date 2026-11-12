local util = require("util")
local settings = require("settings")
local hud = require("hud")
local menu = require("menu")

local TICK_MS = 50

settings.load()

local lastTick = os.clock()

local function tick()
    local now = os.clock()
    hud.tick(now, now - lastTick)
    menu.tick(now)
    settings.update(now)
    lastTick = now
end

local tickQueued = false

LoopAsync(TICK_MS, function()
    -- Skip queueing while the game thread is busy, e.g. on loading screens.
    if not tickQueued then
        tickQueued = true
        ExecuteInGameThread(function()
            tickQueued = false
            local ok, err = pcall(tick)
            if not ok then
                util.warnOnce("tick:" .. tostring(err), "Error while updating the HUD: " .. tostring(err))
            end
        end)
    end
    return false
end)

RegisterKeyBind(Key.ESCAPE, function()
    ExecuteInGameThread(function()
        if menu.isOpen() then
            menu.close()
        end
    end)
end)

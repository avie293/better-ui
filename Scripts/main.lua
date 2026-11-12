local util = require("util")
local settings = require("settings")
local hud = require("hud")
local menu = require("menu")
local theme = require("theme")

local LOOP_MS = 16
local TICK_INTERVAL = 0.05

settings.load()
theme.start()

local lastTick = os.clock()

local function update()
    local now = os.clock()
    if menu.isOpen() then
        menu.frame(now)
    end
    if now - lastTick >= TICK_INTERVAL then
        hud.tick(now, now - lastTick)
        menu.tick(now)
        settings.update(now)
        lastTick = now
    end
end

local queued = false
local nextQueue = 0

-- One loop for everything: it runs every frame while the settings window is open and at the HUD tick
-- rate otherwise. Work is skipped while the game thread is busy, e.g. on loading screens.
LoopAsync(LOOP_MS, function()
    local now = os.clock()
    if not queued and (menu.isOpen() or now >= nextQueue) then
        queued = true
        nextQueue = now + TICK_INTERVAL
        ExecuteInGameThread(function()
            queued = false
            local ok, err = pcall(update)
            if not ok then
                util.warnOnce("update:" .. tostring(err), "Error while updating the HUD: " .. tostring(err))
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

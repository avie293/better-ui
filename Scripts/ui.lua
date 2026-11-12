local util = require("util")

-- Access to Palworld's UI without keeping references that the game may free.
--
-- Lua holds raw pointers, and touching an object after the game freed it crashes, even through IsValid.
-- Looking objects up again is no way out either: StaticFindObject and FindAllOf scan every object and take
-- several milliseconds each. Instead everything is reached from the root UI layout, which lives until the
-- next map load, through the CommonUI layers it shows. Whatever a layer currently displays is alive.

local SEARCH_DELAY = 2
local SEARCH_INTERVAL = 5
local ROOT_CLASS = "WBP_PalOverallUILayout_C"

local ui = {}

local root
local layers = {}
local loading = false
local nextSearch = 0
local resetListeners = {}

local function reset()
    root = nil
    layers = {}
    for _, listener in ipairs(resetListeners) do
        listener()
    end
end

-- Called when every reference into the UI has to be dropped.
function ui.onReset(listener)
    resetListeners[#resetListeners + 1] = listener
end

RegisterLoadMapPreHook(function()
    loading = true
    reset()
end)

RegisterLoadMapPostHook(function()
    loading = false
    nextSearch = os.clock() + SEARCH_DELAY
end)

local function findRoot(now)
    if loading or now < nextSearch then
        return nil
    end
    nextSearch = now + SEARCH_INTERVAL
    for _, layout in ipairs(FindAllOf(ROOT_CLASS) or {}) do
        if layout:IsValid() and layout:IsInViewport() then
            return layout
        end
    end
    return nil
end

function ui.root(now)
    if not root then
        root = findRoot(now)
    end
    return root
end

-- A named widget in the root layout, e.g. a layer or the root panel. It lives as long as the root.
function ui.find(name, now)
    if not ui.root(now) then
        return nil
    end
    local widget = layers[name]
    if widget == nil then
        widget = util.findInTree(root, name) or false
        layers[name] = widget
    end
    return widget or nil
end

-- The widget a layer currently shows: Layer_0 holds the HUD, Layer_2 the pause menu.
function ui.active(layerName, now)
    local layer = ui.find(layerName, now)
    if not layer then
        return nil
    end
    local widget = layer:GetActiveWidget()
    if widget and widget:IsValid() then
        return widget
    end
    return nil
end

return ui

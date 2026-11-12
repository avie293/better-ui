local util = require("util")
local ui = require("ui")
local settings = require("settings")
local ELEMENTS = require("elements")

local REBIND_INTERVAL = 1.0
local ENFORCE_INTERVAL = 1.0
local PROGRESS_EPSILON = 0.001

local valid = util.valid

local hud = {}

hud.ELEMENTS = ELEMENTS
local ELEMENT_BY_ID = {}
for _, element in ipairs(ELEMENTS) do
    ELEMENT_BY_ID[element.id] = element
end
hud.ELEMENT_BY_ID = ELEMENT_BY_ID

local layout
local layoutAddress
local entries = {}
local roots = {}
local unresolved = {}
local nextRebind = 0
local nextEnforce = 0

-- Drops every reference into the HUD without touching it; the widgets may already be freed.
local function forget()
    layout = nil
    layoutAddress = nil
    entries = {}
    roots = {}
    unresolved = {}
end

ui.onReset(forget)

local function readColor(object, property)
    local ok, color = pcall(function()
        local value = object[property]
        return { R = value.R, G = value.G, B = value.B, A = value.A }
    end)
    if ok and type(color.R) == "number" then
        return color
    end
    return nil
end

local function captureOriginal(widget)
    local original = { opacity = widget:GetRenderOpacity(), sx = 1, sy = 1, tx = 0, ty = 0 }
    pcall(function()
        local transform = widget.RenderTransform
        original.sx, original.sy = transform.Scale.X, transform.Scale.Y
        original.tx, original.ty = transform.Translation.X, transform.Translation.Y
    end)
    original.color = readColor(widget, "ColorAndOpacity")
    return original
end

local function toColor(values)
    return { R = values[1] or 1, G = values[2] or 1, B = values[3] or 1, A = values[4] or 1 }
end

local function applyStatic(entry)
    local widget, config, original = entry.widget, entry.config, entry.original
    local scale = config.scale or 1

    widget:SetRenderScale({ X = original.sx * scale, Y = original.sy * scale })
    widget:SetRenderTranslation({ X = original.tx + (config.x or 0), Y = original.ty + (config.y or 0) })

    if (config.tint or entry.tinted) and original.color then
        local color = original.color
        if config.tint then
            local tint = toColor(config.tint)
            color = { R = color.R * tint.R, G = color.G * tint.G, B = color.B * tint.B, A = color.A * tint.A }
        end
        widget:SetColorAndOpacity(color)
        entry.tinted = config.tint ~= nil
    end

    if (config.bar_color or entry.barColored) and valid(entry.bar) and entry.originalBarColor then
        entry.bar:SetFillColorAndOpacity(config.bar_color and toColor(config.bar_color) or entry.originalBarColor)
        entry.barColored = config.bar_color ~= nil
    end
end

local function restore(entry)
    local original = entry.original
    entry.widget:SetRenderOpacity(original.opacity)
    entry.widget:SetRenderScale({ X = original.sx, Y = original.sy })
    entry.widget:SetRenderTranslation({ X = original.tx, Y = original.ty })
    if entry.tinted and original.color then
        entry.widget:SetColorAndOpacity(original.color)
    end
    if entry.barColored and valid(entry.bar) and entry.originalBarColor then
        entry.bar:SetFillColorAndOpacity(entry.originalBarColor)
    end
end

-- Roots are children of the HUD layout, so they live as long as the layout is shown.
local function rootFor(className)
    local root = roots[className]
    if root == nil then
        root = util.findInTree(layout, util.isClass(className)) or false
        roots[className] = root
        if root and className == ELEMENT_BY_ID.hud.root then
            util.log("Attached to the HUD, preset: " .. settings.activePreset())
        end
    end
    return root or nil
end

local function createEntry(element, config)
    local root = rootFor(element.root)
    if not root then
        return nil
    end
    -- Widgets that are missing in this HUD are only looked up again once the HUD is recreated.
    if unresolved[element.id] then
        return nil
    end
    local widget = util.resolve(root, element.path)
    if not widget then
        unresolved[element.id] = true
        util.warnOnce("missing:" .. element.id, "Could not find the widget for '" .. element.id .. "'")
        return nil
    end

    local entry = {
        id = element.id,
        config = config,
        widget = widget,
        original = captureOriginal(widget),
        watches = {},
        visibleUntil = 0,
    }
    entry.current = entry.original.opacity
    entry.applied = entry.current

    for _, watch in ipairs(element.watch or {}) do
        local target = util.resolve(root, watch.path)
        if target then
            entry.watches[#entry.watches + 1] = { definition = watch, widget = target }
            if watch.progress and not entry.bar then
                entry.bar = target
                entry.originalBarColor = readColor(target, "FillColorAndOpacity")
            end
        end
    end
    return entry
end

local function bind()
    for id, config in pairs(settings.active()) do
        local element = ELEMENT_BY_ID[id]
        if element and type(config) == "table" and not entries[id] then
            local entry = createEntry(element, config)
            if entry then
                entries[id] = entry
                applyStatic(entry)
            end
        end
    end
end

-- Applies changed settings right away and restores elements that the active preset no longer touches.
function hud.refresh()
    local active = settings.active()
    for id, entry in pairs(entries) do
        local config = active[id]
        if type(config) == "table" then
            entry.config = config
            applyStatic(entry)
        else
            restore(entry)
            entries[id] = nil
        end
    end
    nextRebind = 0
end

-- Shows auto elements for a moment, e.g. while their settings are edited.
function hud.reveal(id, seconds)
    local entry = entries[id]
    if entry then
        entry.visibleUntil = os.clock() + seconds
    end
end

local function readWatch(watch)
    if watch.definition.progress then
        return watch.widget.Percent
    end
    return watch.widget:GetText():ToString()
end

local function updateAuto(entry, now)
    local config = entry.config
    local active = false
    for _, watch in ipairs(entry.watches) do
        if valid(watch.widget) then
            local value = readWatch(watch)
            local definition = watch.definition
            local below = definition.below and (config.below or definition.below)
            if below and value < below then
                active = true
            end
            local last = watch.last
            if last ~= nil then
                local changed
                if definition.progress then
                    changed = math.abs(value - last) > PROGRESS_EPSILON
                else
                    changed = value ~= last
                end
                if changed then
                    entry.visibleUntil = now + (config.seconds or settings.get("auto_seconds"))
                end
            end
            watch.last = value
        end
    end
    return active or now < entry.visibleUntil
end

local function targetOpacity(entry, now)
    local config = entry.config
    if config.mode == "hide" then
        return 0
    end
    local opacity = entry.original.opacity * (config.opacity or 1)
    if config.mode == "auto" and #entry.watches > 0 then
        return updateAuto(entry, now) and opacity or 0
    end
    return opacity
end

function hud.tick(now, dt)
    local shown = ui.active("Layer_0", now)
    if not shown then
        if layout then
            forget()
        end
        return
    end
    local address = shown:GetAddress()
    if address ~= layoutAddress then
        forget()
        layout = shown
        layoutAddress = address
        nextRebind = 0
    end
    if now >= nextRebind then
        nextRebind = now + REBIND_INTERVAL
        bind()
    end

    local enforce = now >= nextEnforce
    if enforce then
        nextEnforce = now + ENFORCE_INTERVAL
    end

    local fade = settings.get("fade_seconds")
    for _, entry in pairs(entries) do
        local target = targetOpacity(entry, now)
        local current = entry.current
        if current ~= target then
            if fade > 0 then
                local step = dt / fade
                current = target > current and math.min(target, current + step) or math.max(target, current - step)
            else
                current = target
            end
            entry.current = current
        end
        -- The game sets the opacity of some widgets itself, so it is checked again once per second.
        if current ~= entry.applied or (enforce and math.abs(entry.widget:GetRenderOpacity() - current) > 0.01) then
            entry.widget:SetRenderOpacity(current)
            entry.applied = current
        end
    end
end

return hud

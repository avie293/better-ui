local util = require("util")
local ui = require("ui")
local settings = require("settings")

-- Restyles Palworld's menus.
--
-- The first time a menu is shown, its widgets are styled once, together with the widget templates of every
-- widget blueprint class in it. New widgets copy their tree from these templates, so later menus of the same
-- classes come out styled without any further work. Only widgets that the game shows right now are touched.

local HIDDEN = 2

-- Slate colors are linear; these values are linear too, matching what the game uses.
local PALETTES = {
    accent = {
        { name = "Blue", color = { 0.00, 0.42, 1.00 } },
        { name = "Cyan", color = { 0.00, 0.75, 0.90 } },
        { name = "Teal", color = { 0.00, 0.62, 0.45 } },
        { name = "Green", color = { 0.15, 0.75, 0.10 } },
        { name = "Purple", color = { 0.45, 0.15, 1.00 } },
        { name = "Pink", color = { 1.00, 0.20, 0.55 } },
        { name = "Red", color = { 1.00, 0.08, 0.06 } },
        { name = "Orange", color = { 1.00, 0.35, 0.02 } },
        { name = "Gold", color = { 1.00, 0.65, 0.05 } },
        { name = "White", color = { 0.85, 0.85, 0.85 } },
    },
    background = {
        { name = "Vanilla" },
        { name = "Graphite", color = { 0.045, 0.047, 0.052 } },
        { name = "Midnight", color = { 0.010, 0.016, 0.045 } },
        { name = "Black", color = { 0.004, 0.004, 0.004 } },
        { name = "Navy", color = { 0.008, 0.030, 0.090 } },
        { name = "Forest", color = { 0.010, 0.040, 0.020 } },
        { name = "Wine", color = { 0.060, 0.008, 0.020 } },
        { name = "Slate", color = { 0.090, 0.110, 0.140 } },
    },
    text = {
        { name = "Vanilla" },
        { name = "White", color = { 1.00, 1.00, 1.00 } },
        { name = "Soft", color = { 0.80, 0.80, 0.80 } },
        { name = "Warm", color = { 1.00, 0.88, 0.72 } },
        { name = "Cool", color = { 0.78, 0.90, 1.00 } },
    },
    highlight = {
        { name = "Orange", color = { 1.00, 0.68, 0.00 } },
        { name = "Gold", color = { 1.00, 0.85, 0.20 } },
        { name = "Pink", color = { 1.00, 0.30, 0.60 } },
        { name = "Cyan", color = { 0.10, 0.90, 1.00 } },
        { name = "Green", color = { 0.30, 1.00, 0.30 } },
    },
}

local DENSITY = { compact = 0.6, default = 1.0, spacious = 1.4 }

-- Ready-made combinations for the settings window.
local PRESETS = {
    { name = "Vanilla", enabled = false },
    { name = "Clean", accent = "Blue", background = "Graphite", text = "Soft", highlight = "Orange" },
    { name = "Teal", accent = "Teal", background = "Graphite", text = "Soft", highlight = "Gold" },
    { name = "Midnight", accent = "Purple", background = "Midnight", text = "Cool", highlight = "Pink" },
    { name = "Ember", accent = "Orange", background = "Black", text = "Warm", highlight = "Gold" },
    { name = "Forest", accent = "Green", background = "Forest", text = "Warm", highlight = "Gold" },
    { name = "Mono", accent = "White", background = "Black", text = "Soft", highlight = "Gold" },
}
local PRESET_FIELDS = { "accent", "background", "text", "highlight" }

-- Purely decorative images: dot patterns, flares, triangle patterns and drop shadows.
local DECORATION_NAMES = {
    "^Dot$", "^Dot_%d+$", "^Dot%d+$", "_Dot$", "_Dot_%d+$",
    "Flare", "^Tri$", "^Tri_%d+$", "^tri$", "^tri_%d+$", "_tri$", "_tri_%d+$", "Tri_%d+$", "_Tri$",
    "^BaseShadow", "^BG_Tri", "Pattern",
}
local DECORATION_TEXTURES = {
    T_prt_frame_flare = true,
    T_prt_button_frame_flare = true,
    T_eff_flare_00 = true,
    T_prt_menutab_tri = true,
    T_prt_pal_select_base_tri = true,
    T_prt_menu_pal_base_tri = true,
}

-- Images that make up panels and buttons. Anything else, like icons, rarity and element colors, keeps its color.
local STRUCTURE_NAMES = {
    "^Base", "Base$", "Base_", "^Frame", "Frame$", "Frame_", "Focus", "^Active", "Line", "Background", "^Bg",
    "^BG", "^Tab", "Select", "Cursor", "Hover", "^Head", "Header", "Board", "^Image$", "^Image_%d+$",
}
local PROTECTED_NAMES = { "Icon", "icon", "Rarity", "Rare", "Element", "Skill", "Mutant", "Strong", "Red", "Gauge",
    "Doping", "Awakening", "Item", "Pal", "Hp", "HP", "Curse", "Seed" }
local PROTECTED_TEXTURES = { "icon", "Icon", "T_itemicon", "T_pal", "T_ui_pal", "Notice" }
-- Never hidden: focus frames show the selected button, notice and NEW dots show unread content.
local KEEP_NAMES = { "Focus", "Notice", "New", "NEW", "Red", "Select" }

local function matchesAny(text, patterns)
    for i = 1, #patterns do
        if text:find(patterns[i]) then
            return true
        end
    end
    return false
end

local function containsAny(text, needles)
    for i = 1, #needles do
        if text:find(needles[i], 1, true) then
            return true
        end
    end
    return false
end

-- Theme -----------------------------------------------------------------------------------------------

local function paletteColor(kind, name)
    for _, entry in ipairs(PALETTES[kind]) do
        if entry.name == name then
            return entry.color
        end
    end
    return PALETTES[kind][1].color
end

local active

local function buildTheme()
    local config = settings.get("theme")
    if not config.enabled then
        return nil
    end
    return {
        accent = paletteColor("accent", config.accent),
        background = paletteColor("background", config.background),
        text = paletteColor("text", config.text),
        highlight = paletteColor("highlight", config.highlight),
        decorations = config.decorations,
        blur = config.blur,
        density = DENSITY[settings.get("density")] or 1,
    }
end

-- Colors ---------------------------------------------------------------------------------------------

local function family(c)
    local high = math.max(c.R, c.G, c.B)
    if high <= 0.2 then
        return "dark"
    end
    if c.B >= 0.6 and c.R <= 0.35 and c.B >= c.G then
        return "accent"
    end
    if c.R >= 0.8 and c.G >= 0.3 and c.G <= 0.8 and c.B <= 0.25 then
        return "highlight"
    end
    if math.min(c.R, c.G, c.B) >= 0.85 then
        return "white"
    end
    return nil
end

-- Keeps the brightness differences of the original colors, e.g. lighter and darker shades of the accent.
local function tinted(original, target)
    local high = math.max(original.R, original.G, original.B)
    local low = math.min(original.R, original.G, original.B)
    local function channel(value)
        return (value + (1 - value) * low) * high
    end
    return { R = channel(target[1]), G = channel(target[2]), B = channel(target[3]), A = original.A }
end

-- Near-black panels become the background color, lighter dark shades become lighter shades of it.
local function darkened(original, target)
    local factor = math.min(2.5, 1 + math.max(0, math.max(original.R, original.G, original.B) - 0.06) * 5)
    return { R = target[1] * factor, G = target[2] * factor, B = target[3] * factor, A = original.A }
end

-- Translucent white frames and lines take on the accent color.
local LINE_TINT = 0.65

local function lined(original, target)
    local function channel(value)
        return 1 + (value - 1) * LINE_TINT
    end
    return { R = channel(target[1]), G = channel(target[2]), B = channel(target[3]), A = original.A }
end

local function imageColor(original, kind)
    local t = active
    if kind == "accent" then
        return tinted(original, t.accent)
    elseif kind == "highlight" then
        return tinted(original, t.highlight)
    elseif kind == "dark" and t.background then
        return darkened(original, t.background)
    elseif kind == "white" and original.A < 0.95 then
        return lined(original, t.accent)
    end
    return nil
end

local function textColor(original, kind)
    local t = active
    if kind == "white" and t.text then
        return { R = t.text[1], G = t.text[2], B = t.text[3], A = original.A }
    elseif kind == "accent" then
        return tinted(original, t.accent)
    elseif kind == "highlight" then
        return tinted(original, t.highlight)
    end
    return nil
end

-- Templates ------------------------------------------------------------------------------------------

-- Original values by "<class>/<widget>", captured before the first change so a theme can be swapped or removed.
local originals = {}

local function readColor(value)
    return { R = value.R, G = value.G, B = value.B, A = value.A }
end

local function resourceName(image)
    local ok, name = pcall(function()
        local resource = image.Brush.ResourceObject
        return resource and resource:IsValid() and resource:GetFName():ToString() or ""
    end)
    return ok and name or ""
end

local function capture(node, kind)
    local original = { kind = kind }
    if kind == "image" then
        original.color = readColor(node.ColorAndOpacity)
        original.visibility = node:GetVisibility()
        original.resource = resourceName(node)
    elseif kind == "text" then
        original.color = readColor(node.ColorAndOpacity.SpecifiedColor)
    elseif kind == "blur" then
        original.blur = node.BlurStrength
    end
    local slot = node.Slot
    if slot and slot:IsValid() then
        local slotClass = util.className(slot)
        if slotClass == "VerticalBoxSlot" or slotClass == "HorizontalBoxSlot" then
            local padding = slot.Padding
            original.padding = {
                Left = padding.Left,
                Top = padding.Top,
                Right = padding.Right,
                Bottom = padding.Bottom,
            }
        end
    end
    return original
end

local function isDecoration(name, resource)
    return (matchesAny(name, DECORATION_NAMES) or DECORATION_TEXTURES[resource])
        and not containsAny(resource, PROTECTED_TEXTURES) and not containsAny(name, KEEP_NAMES)
end

local function isStructure(name, resource)
    return matchesAny(name, STRUCTURE_NAMES) and not containsAny(name, PROTECTED_NAMES)
        and not containsAny(resource, PROTECTED_TEXTURES)
end

local function styleImage(node, name, original)
    if isDecoration(name, original.resource) then
        if active and not active.decorations then
            node:SetVisibility(HIDDEN)
        elseif node:GetVisibility() == HIDDEN then
            -- Only undo the hiding; the game may have hidden or shown the widget itself since.
            node:SetVisibility(original.visibility)
        end
        return
    end
    local color
    if active and isStructure(name, original.resource) then
        color = imageColor(original.color, family(original.color))
    end
    node:SetColorAndOpacity(color or original.color)
end

local function styleNode(node, owner)
    local nodeClass = util.className(node)
    local kind
    if nodeClass == "Image" then
        kind = "image"
    elseif nodeClass:find("TextBlock", 1, true) and not nodeClass:find("Rich", 1, true) then
        kind = "text"
    elseif nodeClass == "BackgroundBlur" then
        kind = "blur"
    end

    local name = node:GetFName():ToString()
    local key = owner .. "/" .. name
    local original = originals[key]
    if not original then
        original = capture(node, kind)
        originals[key] = original
    end

    if kind == "image" then
        styleImage(node, name, original)
    elseif kind == "text" then
        local color = active and textColor(original.color, family(original.color))
        node:SetColorAndOpacity({ SpecifiedColor = color or original.color, ColorUseRule = 0 })
    elseif kind == "blur" then
        node:SetBlurStrength(original.blur * (active and active.blur or 1))
    end

    if original.padding then
        local factor = active and active.density or 1
        local p = original.padding
        node.Slot:SetPadding({ Left = p.Left * factor, Top = p.Top * factor, Right = p.Right * factor,
            Bottom = p.Bottom * factor })
    end
end

local function styleTemplate(class, owner)
    local tree = class.WidgetTree
    if not (tree and tree:IsValid()) then
        return
    end
    local queue = { tree.RootWidget }
    local head = 1
    while queue[head] do
        local node = queue[head]
        queue[head] = false
        head = head + 1
        if util.valid(node) then
            styleNode(node, owner)
            -- Nested user widgets are styled through their own class.
            if not util.nestedTree(node) then
                local ok, slots, count = pcall(function()
                    local value = node.Slots
                    return value, #value
                end)
                if ok then
                    for i = 1, count do
                        local content = slots[i] and slots[i].Content
                        if util.valid(content) then
                            queue[#queue + 1] = content
                        end
                    end
                end
            end
        end
    end
end

-- Animations ---------------------------------------------------------------------------------------

-- Focus, hover and selection colors are set by widget animations, so their color keys are themed as well.
local CHANNELS = { "RedCurve", "GreenCurve", "BlueCurve", "AlphaCurve" }

local function styleSection(section, key)
    local values = {}
    local count
    for i, channel in ipairs(CHANNELS) do
        values[i] = section[channel].Values
        local length = #values[i]
        if count and length ~= count then
            return
        end
        count = length
    end
    local original = originals[key]
    if not original then
        original = {}
        for k = 1, count do
            original[k] = { R = values[1][k].Value, G = values[2][k].Value, B = values[3][k].Value,
                A = values[4][k].Value }
        end
        originals[key] = original
    end
    for k = 1, count do
        local color = original[k]
        local styled = active and imageColor(color, family(color)) or color
        values[1][k].Value = styled.R
        values[2][k].Value = styled.G
        values[3][k].Value = styled.B
    end
end

local function styleAnimations(class, owner)
    local animations = class.Animations
    for a = 1, #animations do
        local animation = animations[a]
        local scene = animation.MovieScene
        if util.valid(scene) then
            local animationName = animation:GetFName():ToString()
            local bindings = scene.ObjectBindings
            for b = 1, #bindings do
                local binding = bindings[b]
                local name = binding.BindingName:ToString()
                local widget = originals[owner .. "/" .. name]
                -- Only images that the template pass identified as part of a panel or button.
                if widget and widget.kind == "image" and isStructure(name, widget.resource) then
                    local tracks = binding.Tracks
                    for t = 1, #tracks do
                        local track = tracks[t]
                        if util.className(track) == "MovieSceneColorTrack"
                            and track.PropertyBinding.PropertyPath:ToString() == "ColorAndOpacity" then
                            local sections = track.Sections
                            for s = 1, #sections do
                                local key = owner .. "#" .. animationName .. "#" .. name .. "#" .. t .. "#" .. s
                                styleSection(sections[s], key)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function styleClass(class)
    local owner = class:GetFName():ToString()
    styleTemplate(class, owner)
    styleAnimations(class, owner)
end

-- Live menus ---------------------------------------------------------------------------------------

local LAYERS = { "Layer_0", "Layer_1", "Layer_2", "Layer_3", "Layer_4", "Layer_5", "Layer_6", "Layer_7", "Menu",
    "Modal" }

-- Classes whose template and animations use the current theme.
local styledClasses = {}
-- Classes whose shown widgets were walked once, so later widgets of them come from styled templates.
local walkedClasses = {}
-- Address of the widget each layer showed last time.
local shown = {}

local function ensureClass(class)
    local address = class:GetAddress()
    if styledClasses[address] then
        return
    end
    styledClasses[address] = true
    local ok, err = pcall(styleClass, class)
    if not ok then
        util.warnOnce("theme:" .. tostring(err),
            "Could not style " .. class:GetFName():ToString() .. ": " .. tostring(err))
    end
end

-- Styles a shown widget and everything in it. Plain user widgets, like the settings window, are left alone.
local function styleLive(widget)
    local queue = { { node = widget } }
    local head = 1
    while queue[head] do
        local item = queue[head]
        queue[head] = false
        head = head + 1
        local node, owner = item.node, item.owner
        if util.valid(node) then
            local tree = util.nestedTree(node)
            if tree then
                local class = node:GetClass()
                if util.className(class) == "WidgetBlueprintGeneratedClass" then
                    ensureClass(class)
                    queue[#queue + 1] = { node = tree.RootWidget, owner = class:GetFName():ToString() }
                end
            else
                if owner then
                    styleNode(node, owner)
                end
                local ok, slots, count = pcall(function()
                    local value = node.Slots
                    return value, #value
                end)
                if ok then
                    for i = 1, count do
                        local content = slots[i].Content
                        if util.valid(content) then
                            queue[#queue + 1] = { node = content, owner = owner }
                        end
                    end
                end
            end
        end
    end
end

ui.onReset(function()
    shown = {}
end)

local theme = {}
theme.PALETTES = PALETTES
theme.PRESETS = PRESETS

function theme.paletteColor(kind, name)
    return paletteColor(kind, name)
end

function theme.applyPreset(preset)
    settings.setTheme("enabled", preset.enabled ~= false)
    for _, field in ipairs(PRESET_FIELDS) do
        if preset[field] then
            settings.setTheme(field, preset[field])
        end
    end
end

function theme.isPresetActive(preset)
    local config = settings.get("theme")
    if preset.enabled == false or not config.enabled then
        return preset.enabled == false and not config.enabled
    end
    for _, field in ipairs(PRESET_FIELDS) do
        if config[field] ~= preset[field] then
            return false
        end
    end
    return true
end

-- Styles menus that are shown for the first time.
function theme.tick(now)
    for _, layerName in ipairs(LAYERS) do
        local widget = ui.active(layerName, now)
        local address = widget and widget:GetAddress()
        if address ~= shown[layerName] then
            shown[layerName] = address
            if widget then
                local class = widget:GetClass():GetAddress()
                if not walkedClasses[class] then
                    walkedClasses[class] = true
                    styleLive(widget)
                end
            end
        end
    end
end

-- Uses the current settings for every template and restyles everything that is shown right now,
-- including widgets that live outside the layers, like the focus cursor.
function theme.apply(now)
    active = buildTheme()
    styledClasses = {}
    walkedClasses = {}
    shown = {}
    local root = ui.root(now)
    if root then
        styleLive(root)
    end
    theme.tick(now)
end

function theme.start()
    active = buildTheme()
end

return theme

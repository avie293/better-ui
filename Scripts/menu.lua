local util = require("util")
local ui = require("ui")
local settings = require("settings")
local hud = require("hud")

local valid = util.valid

local ENTRY_LABEL = "HUD Layout"

local WINDOW_WIDTH, WINDOW_HEIGHT = 940, 600
local REPEAT_DELAY, REPEAT_INTERVAL = 0.45, 0.07

local VISIBLE, COLLAPSED = 0, 1
local FILL = { SizeRule = 1, Value = 1 }
local ALIGN_FILL, ALIGN_LEFT, ALIGN_CENTER = 0, 1, 2

-- Slate colors are linear, these are written as sRGB to match what is seen on screen.
local function srgb(r, g, b, a)
    return { r ^ 2.2, g ^ 2.2, b ^ 2.2, a or 1 }
end

local COLOR = {
    window = srgb(0.07, 0.08, 0.1, 0.96),
    button = srgb(0.15, 0.17, 0.21),
    hover = srgb(0.22, 0.25, 0.31),
    active = srgb(0.16, 0.5, 0.75),
    activeHover = srgb(0.22, 0.58, 0.83),
    text = srgb(0.93, 0.94, 0.96),
    dim = srgb(0.6, 0.63, 0.68),
    transparent = { 1, 1, 1, 0 },
}

local TINTS = {
    { name = "Default" },
    { name = "Soft", color = { 0.9, 0.9, 0.9, 0.85 } },
    { name = "Warm", color = { 1, 0.9, 0.75, 1 } },
    { name = "Cool", color = { 0.8, 0.9, 1, 1 } },
    { name = "Mint", color = { 0.75, 1, 0.85, 1 } },
    { name = "Gold", color = { 1, 0.85, 0.45, 1 } },
    { name = "Rose", color = { 1, 0.75, 0.8, 1 } },
    { name = "Gray", color = { 0.65, 0.65, 0.65, 1 } },
}

local BAR_COLORS = {
    { name = "Default" },
    { name = "Green", color = { 0.3, 0.85, 0.4, 1 } },
    { name = "Teal", color = { 0.2, 0.8, 0.75, 1 } },
    { name = "Blue", color = { 0.3, 0.6, 1, 1 } },
    { name = "Red", color = { 0.9, 0.25, 0.25, 1 } },
    { name = "Orange", color = { 1, 0.6, 0.2, 1 } },
    { name = "Gold", color = { 1, 0.8, 0.25, 1 } },
    { name = "Purple", color = { 0.65, 0.45, 1, 1 } },
    { name = "White", color = { 0.95, 0.95, 0.95, 1 } },
}

local menu = {}

local classes = {}
local library
local window
local tree
local controls = {}
local clickables = {}
local selected = hud.ELEMENTS[1].id
local isOpen = false

local escEntry
local gameFont

-- Helpers -------------------------------------------------------------------------------------

local function linear(values)
    return { R = values[1], G = values[2], B = values[3], A = values[4] }
end

local function construct(name)
    local class = classes[name]
    if not class then
        class = StaticFindObject("/Script/UMG." .. name)
        classes[name] = class
    end
    return StaticConstructObject(class, tree)
end

local function round(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function sameColor(a, b)
    if a == nil or b == nil then
        return a == b
    end
    for i = 1, 4 do
        if math.abs((a[i] or 1) - (b[i] or 1)) > 0.001 then
            return false
        end
    end
    return true
end

local function paletteIndex(palette, color)
    for i, entry in ipairs(palette) do
        if sameColor(entry.color, color) then
            return i
        end
    end
    return nil
end

-- Widget building -----------------------------------------------------------------------------

local function setFont(text, size)
    pcall(function()
        local font = text.Font
        text:SetFont({
            FontObject = gameFont and gameFont.FontObject or font.FontObject,
            TypefaceFontName = gameFont and gameFont.TypefaceFontName or font.TypefaceFontName,
            Size = size,
        })
    end)
end

local function setTextColor(text, color)
    text:SetColorAndOpacity({ SpecifiedColor = linear(color), ColorUseRule = 0 })
end

local function makeText(label, size, color)
    local text = construct("TextBlock")
    text:SetText(FText(label))
    setFont(text, size)
    setTextColor(text, color or COLOR.text)
    return text
end

local function sized(widget, width, height)
    local box = construct("SizeBox")
    if width then
        box:SetWidthOverride(width)
    end
    if height then
        box:SetHeightOverride(height)
    end
    box:AddChild(widget)
    return box
end

local function addTo(box, widget, padding, fill, verticalAlignment)
    local slot
    if box:GetClass():GetFName():ToString() == "HorizontalBox" then
        slot = box:AddChildToHorizontalBox(widget)
    else
        slot = box:AddChildToVerticalBox(widget)
    end
    if padding then
        slot:SetPadding(padding)
    end
    if fill then
        slot:SetSize(FILL)
    end
    slot:SetVerticalAlignment(verticalAlignment or ALIGN_FILL)
    return slot
end

local function margin(left, top, right, bottom)
    return { Left = left, Top = top, Right = right, Bottom = bottom }
end

local function fillOverlay(overlay, widget)
    local slot = overlay:AddChildToOverlay(widget)
    slot:SetHorizontalAlignment(ALIGN_FILL)
    slot:SetVerticalAlignment(ALIGN_FILL)
end

-- The engine's button style adds its own padding and cannot be restyled from Lua, so an invisible button
-- is laid over a border that draws the background. Hover and press states are polled every frame.
local function makeButton(label, action, options)
    options = options or {}
    local border = construct("Border")
    border:SetBrushColor(linear(COLOR.button))
    border:SetPadding(margin(10, 0, 10, 0))
    border:SetHorizontalAlignment(options.left and ALIGN_LEFT or ALIGN_CENTER)
    border:SetVerticalAlignment(ALIGN_CENTER)
    local text = makeText(label, options.size or 15)
    border:AddChild(text)
    local button = construct("Button")
    button:SetBackgroundColor(linear(COLOR.transparent))
    local overlay = construct("Overlay")
    fillOverlay(overlay, border)
    fillOverlay(overlay, button)

    local clickable = {
        button = button,
        border = border,
        text = text,
        action = action,
        repeatable = options.repeatable,
        active = false,
    }
    clickables[#clickables + 1] = clickable
    return clickable, sized(overlay, options.width, options.height or 32)
end

local function setActive(clickable, active)
    clickable.active = active
    clickable.shownColor = nil
end

local function makeRow(parent, label)
    local row = construct("HorizontalBox")
    addTo(row, sized(makeText(label, 15, COLOR.dim), 150), margin(0, 0, 8, 0), false, ALIGN_CENTER)
    addTo(parent, row, margin(0, 3, 0, 3))
    return row
end

local function makeStepper(parent, label, onStep)
    local row = makeRow(parent, label)
    local _, minus = makeButton("-", function()
        onStep(-1)
    end, { width = 40, repeatable = true })
    local value = makeText("", 15)
    value:SetJustification(1)
    local _, plus = makeButton("+", function()
        onStep(1)
    end, { width = 40, repeatable = true })
    addTo(row, minus)
    addTo(row, sized(value, 110), margin(4, 0, 4, 0), false, ALIGN_CENTER)
    addTo(row, plus)
    return row, value
end

-- Settings changes ----------------------------------------------------------------------------

local function current()
    return settings.element(selected) or {}
end

local function element()
    return hud.ELEMENT_BY_ID[selected]
end

local function defaultBelow()
    for _, watch in ipairs(element().watch or {}) do
        if watch.below then
            return watch.below
        end
    end
    return nil
end

local function change(key, value)
    settings.setValue(selected, key, value)
    hud.refresh()
    menu.refreshWindow()
end

local function stepNumber(key, step, low, high, default, direction)
    local value = round(clamp((current()[key] or default) + step * direction, low, high))
    change(key, value ~= default and value or nil)
end

local function cyclePalette(key, palette, direction)
    local index = paletteIndex(palette, current()[key]) or 1
    index = (index - 1 + direction) % #palette + 1
    change(key, palette[index].color)
end

-- Window --------------------------------------------------------------------------------------

local function buildWindow(controller)
    local _
    library = library or StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    window = library:Create(controller, StaticFindObject("/Script/UMG.UserWidget"), controller)
    tree = window.WidgetTree
    clickables = {}
    controls = {}
    pcall(function()
        window.bIsFocusable = true
    end)

    local canvas = construct("CanvasPanel")
    tree.RootWidget = canvas

    local frame = construct("Border")
    frame:SetBrushColor(linear(COLOR.window))
    frame:SetPadding(margin(20, 16, 20, 16))
    local frameSlot = canvas:AddChildToCanvas(frame)
    frameSlot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    frameSlot:SetAlignment({ X = 0.5, Y = 0.5 })
    frameSlot:SetPosition({ X = 0, Y = 0 })
    frameSlot:SetSize({ X = WINDOW_WIDTH, Y = WINDOW_HEIGHT })

    local layout = construct("VerticalBox")
    frame:AddChild(layout)

    local header = construct("HorizontalBox")
    addTo(header, makeText("Clean Pal UI", 22), nil, true)
    local _, close = makeButton("Close", menu.close, { width = 90 })
    addTo(header, close)
    addTo(layout, header, margin(0, 0, 0, 10))

    local presets = construct("HorizontalBox")
    addTo(presets, sized(makeText("Preset", 15, COLOR.dim), 80), margin(0, 7, 0, 0))
    controls.presets = {}
    for _, name in ipairs(settings.presetNames()) do
        local label = name:sub(1, 1):upper() .. name:sub(2)
        local clickable, widget = makeButton(label, function()
            settings.setPreset(name)
            hud.refresh()
            menu.refreshWindow()
        end, { width = 110 })
        controls.presets[name] = clickable
        addTo(presets, widget, margin(0, 0, 6, 0))
    end
    addTo(layout, presets, margin(0, 0, 0, 14))

    local content = construct("HorizontalBox")
    addTo(layout, content, nil, true)

    local list = construct("ScrollBox")
    controls.elements = {}
    for _, definition in ipairs(hud.ELEMENTS) do
        local clickable, widget = makeButton(definition.label, function()
            selected = definition.id
            menu.refreshWindow()
        end, { size = 14, height = 30, left = true })
        controls.elements[definition.id] = clickable
        local slot = list:AddChild(widget)
        slot:SetPadding(margin(0, 0, 10, 3))
    end
    addTo(content, sized(list, 330), margin(0, 0, 18, 0))

    local details = construct("VerticalBox")
    addTo(content, details, nil, true)
    controls.title = makeText("", 19)
    addTo(details, controls.title, margin(0, 0, 0, 4))
    controls.hint = makeText("", 13, COLOR.dim)
    controls.hint:SetAutoWrapText(true)
    addTo(details, controls.hint, margin(0, 0, 0, 8))

    local editor = construct("VerticalBox")
    controls.editor = editor
    addTo(details, editor)

    local modeRow = makeRow(editor, "Display")
    controls.modes = {}
    for _, mode in ipairs({ "show", "auto", "hide" }) do
        local label = mode:sub(1, 1):upper() .. mode:sub(2)
        local clickable, widget = makeButton(label, function()
            change("mode", mode ~= "show" and mode or nil)
        end, { width = 80 })
        controls.modes[mode] = { clickable = clickable, widget = widget }
        addTo(modeRow, widget, margin(0, 0, 6, 0))
    end

    _, controls.opacity = makeStepper(editor, "Opacity", function(direction)
        stepNumber("opacity", 0.05, 0.1, 1, 1, direction)
    end)
    _, controls.scale = makeStepper(editor, "Size", function(direction)
        stepNumber("scale", 0.05, 0.5, 2, 1, direction)
    end)
    _, controls.x = makeStepper(editor, "Horizontal", function(direction)
        stepNumber("x", 5, -960, 960, 0, direction)
    end)
    _, controls.y = makeStepper(editor, "Vertical", function(direction)
        stepNumber("y", 5, -540, 540, 0, direction)
    end)
    controls.tintRow, controls.tint = makeStepper(editor, "Color", function(direction)
        cyclePalette("tint", TINTS, direction)
    end)
    controls.barRow, controls.bar = makeStepper(editor, "Bar color", function(direction)
        cyclePalette("bar_color", BAR_COLORS, direction)
    end)
    controls.secondsRow, controls.seconds = makeStepper(editor, "Auto duration", function(direction)
        stepNumber("seconds", 1, 1, 30, settings.get("auto_seconds"), direction)
    end)
    controls.belowRow, controls.below = makeStepper(editor, "Auto below", function(direction)
        stepNumber("below", 0.05, 0.05, 1, defaultBelow(), direction)
    end)

    local actions = construct("HorizontalBox")
    local _, resetElement = makeButton("Reset element", function()
        settings.resetElement(selected)
        hud.refresh()
        menu.refreshWindow()
    end, { width = 150 })
    local _, resetPreset = makeButton("Reset preset", function()
        settings.resetPreset()
        hud.refresh()
        menu.refreshWindow()
    end, { width = 150 })
    addTo(actions, resetElement, margin(0, 0, 8, 0))
    addTo(actions, resetPreset)
    addTo(editor, actions, margin(0, 14, 0, 0))
end

local function percent(value)
    return string.format("%d%%", math.floor(value * 100 + 0.5))
end

local function setRowVisible(row, visible)
    row:SetVisibility(visible and VISIBLE or COLLAPSED)
end

function menu.refreshWindow()
    if not window then
        return
    end
    local active = settings.activePreset()
    for name, clickable in pairs(controls.presets) do
        setActive(clickable, name == active)
    end
    local preset = settings.active()
    for id, clickable in pairs(controls.elements) do
        setActive(clickable, id == selected)
        local config = preset[id]
        setTextColor(clickable.text, config and config.mode == "hide" and COLOR.dim or COLOR.text)
    end

    local definition = element()
    local config = current()
    controls.title:SetText(FText(definition.label))
    local editable = settings.isEditable()
    setRowVisible(controls.editor, editable)
    if not editable then
        controls.hint:SetText(FText("The Vanilla preset shows the original HUD. Pick another preset to customize it."))
        return
    end
    local supportsAuto = definition.watch ~= nil
    controls.hint:SetText(FText(supportsAuto
        and "Auto shows this element only when it matters and hides it otherwise."
        or "Changes are applied right away and saved automatically."))

    local mode = config.mode or "show"
    for name, entry in pairs(controls.modes) do
        setActive(entry.clickable, name == mode)
    end
    setRowVisible(controls.modes.auto.widget, supportsAuto)

    controls.opacity:SetText(FText(percent(config.opacity or 1)))
    controls.scale:SetText(FText(percent(config.scale or 1)))
    controls.x:SetText(FText(tostring(config.x or 0)))
    controls.y:SetText(FText(tostring(config.y or 0)))

    setRowVisible(controls.tintRow, definition.tint ~= false)
    local tint = paletteIndex(TINTS, config.tint)
    controls.tint:SetText(FText(tint and TINTS[tint].name or "Custom"))

    local hasBar = false
    for _, watch in ipairs(definition.watch or {}) do
        hasBar = hasBar or watch.progress == true
    end
    setRowVisible(controls.barRow, hasBar)
    local bar = paletteIndex(BAR_COLORS, config.bar_color)
    controls.bar:SetText(FText(bar and BAR_COLORS[bar].name or "Custom"))

    local auto = supportsAuto and mode == "auto"
    setRowVisible(controls.secondsRow, auto)
    controls.seconds:SetText(FText(string.format("%d s", config.seconds or settings.get("auto_seconds"))))
    local below = defaultBelow()
    setRowVisible(controls.belowRow, auto and below ~= nil)
    if below then
        controls.below:SetText(FText(percent(config.below or below)))
    end
end

-- Input ---------------------------------------------------------------------------------------

local function pollClickable(clickable, now)
    local button = clickable.button
    local pressed = button:IsPressed()
    if pressed and not clickable.pressed then
        clickable.repeatAt = now + REPEAT_DELAY
        clickable.action()
    elseif pressed and clickable.repeatable and now >= clickable.repeatAt then
        clickable.repeatAt = now + REPEAT_INTERVAL
        clickable.action()
    end
    clickable.pressed = pressed

    local hovered = button:IsHovered()
    local color
    if clickable.active then
        color = hovered and COLOR.activeHover or COLOR.active
    else
        color = hovered and COLOR.hover or COLOR.button
    end
    if clickable.shownColor ~= color then
        clickable.shownColor = color
        clickable.border:SetBrushColor(linear(color))
    end
end

-- Everything below only touches widgets that the game currently shows, see ui.lua.

-- The open pause menu, if any. It is shown on the pause layer while the game is paused.
local function activePauseMenu(now)
    local widget = ui.active("Layer_2", now)
    if widget and util.className(widget) == "WBP_InGameMainMenu_C" then
        return widget
    end
    return nil
end

-- The window stays in the viewport while hidden, so the game keeps it alive until the next map load.
ui.onReset(function()
    window = nil
    tree = nil
    isOpen = false
    escEntry = nil
end)

function menu.open(controller)
    if not window then
        buildWindow(controller)
        window:AddToViewport(500)
    end
    menu.refreshWindow()
    window:SetVisibility(VISIBLE)
    isOpen = true
end

function menu.close()
    if not isOpen then
        return
    end
    isOpen = false
    if window then
        window:SetVisibility(COLLAPSED)
    end
    settings.save()
end

function menu.isOpen()
    return isOpen
end

-- Called every frame while the window is open. The window closes together with the pause menu.
function menu.frame(now)
    if not window or not activePauseMenu(now) then
        menu.close()
        return
    end
    for i = 1, #clickables do
        if not isOpen then
            return
        end
        pollClickable(clickables[i], now)
    end
    -- Keep auto elements visible while they are being edited.
    hud.reveal(selected, 0.2)
end

-- Pause menu entry ----------------------------------------------------------------------------

local function isText(widget)
    return util.className(widget):find("TextBlock", 1, true) ~= nil
end

local isEscMenu = util.isClass("WBP_MenuESC_C")

-- Checks through the live list whether the entry is still in it, without touching the entry itself.
local function hasChild(list, address)
    local ok, slots, count = pcall(function()
        local value = list.Slots
        return value, #value
    end)
    if not ok then
        return false
    end
    for i = 1, count do
        local content = slots[i].Content
        if valid(content) and content:GetAddress() == address then
            return true
        end
    end
    return false
end

-- The entry is a copy of the game's small pause menu button, added below "Link Discord".
local function injectEntry(esc, list, controller)
    local template = util.findInTree(esc, "WBP_MenuESC_Button_S_Discord")
    if not template then
        util.warnOnce("esc", "Could not add the HUD Layout entry to the pause menu")
        return nil
    end
    library = library or StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local entry = library:Create(controller, template:GetClass(), controller)
    local slot = list:AddChildToVerticalBox(entry)
    pcall(function()
        slot:SetPadding(template.Slot.Padding)
    end)
    local text = util.findInTree(entry, "Text_Main") or util.findInTree(entry, isText)
    if text and not gameFont then
        pcall(function()
            local font = text.Font
            gameFont = { FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName }
        end)
    end
    return {
        address = entry:GetAddress(),
        text = text,
        button = util.findInTree(entry, "WBP_PalInvisibleButton"),
        pressed = false,
    }
end

-- The same in-game menu also shows the inventory and other tabs, which replace the ESC menu and with it the
-- entry. So the entry is only used after finding it in the ESC menu that is shown right now.
function menu.tick(now)
    local pauseMenu = activePauseMenu(now)
    if not pauseMenu then
        return
    end
    local esc = util.findInTree(pauseMenu, isEscMenu)
    local list = esc and util.findInTree(esc, "VerticalBox_148")
    if not list then
        return
    end
    if not (escEntry and hasChild(list, escEntry.address)) then
        escEntry = injectEntry(esc, list, pauseMenu:GetOwningPlayer())
        if not escEntry then
            return
        end
    end
    if escEntry.text and escEntry.text:GetText():ToString() ~= ENTRY_LABEL then
        escEntry.text:SetText(FText(ENTRY_LABEL))
    end
    if escEntry.button then
        local pressed = escEntry.button:IsPressed()
        if pressed and not escEntry.pressed and not isOpen then
            menu.open(pauseMenu:GetOwningPlayer())
        end
        escEntry.pressed = pressed
    end
end

return menu

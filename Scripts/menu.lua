local util = require("util")
local settings = require("settings")
local hud = require("hud")
local UEHelpers = require("UEHelpers")

local valid = util.valid

local IN_GAME_MENU = "/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu_C"
local ENTRY_LABEL = "HUD Layout"
local ESC_CHECK_INTERVAL = 0.2

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
local windowHandle
local tree
local controls = {}
local clickables = {}
local selected = hud.ELEMENTS[1].id
local isOpen = false

local escEntry
local entryChecked = false
local nextEscCheck = 0
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
    windowHandle = util.handle(window)
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
    if not util.alive(windowHandle) then
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

local function attached(handle)
    return util.alive(handle) and valid(handle.object:GetParent())
end

-- The pause menu sits in a CommonUI layer, so it has no parent widget; the open one is the activated one.
local function activePauseMenu()
    local list = util.instances(IN_GAME_MENU)
    for i = #list, 1, -1 do
        local handle = list[i]
        local ok, activated = pcall(function()
            return handle.object:IsActivated()
        end)
        if not ok then
            util.warnOnce("activated", "Could not check the pause menu: " .. tostring(activated))
        elseif activated then
            return handle
        end
    end
    return nil
end

function menu.open()
    local controller = UEHelpers.GetPlayerController()
    if not valid(controller) then
        return
    end
    if not util.alive(windowHandle) then
        buildWindow(controller)
    end
    menu.refreshWindow()
    if not window:IsInViewport() then
        window:AddToViewport(500)
    end
    isOpen = true
end

function menu.close()
    if not isOpen then
        return
    end
    isOpen = false
    if util.alive(windowHandle) then
        window:RemoveFromParent()
    end
    settings.save()
end

function menu.isOpen()
    return isOpen
end

-- Called every frame while the window is open.
function menu.frame(now)
    -- The window lives on top of the pause menu and closes together with it.
    if not util.alive(windowHandle) or not window:IsInViewport() or not activePauseMenu() then
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

local function className(widget)
    return widget:GetClass():GetFName():ToString()
end

local function isText(widget)
    return className(widget):find("TextBlock", 1, true) ~= nil
end

local function isEscMenu(widget)
    return className(widget) == "WBP_MenuESC_C"
end

-- The entry is a copy of the game's small pause menu button, added below "Link Discord".
local function injectEntry(esc)
    local list = util.findInTree(esc, "VerticalBox_148")
    local template = util.findInTree(esc, "WBP_MenuESC_Button_S_Discord")
    if not list or not template then
        util.warnOnce("esc", "Could not add the HUD Layout entry to the pause menu")
        return nil
    end
    local controller = UEHelpers.GetPlayerController()
    library = library or StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local entry = library:Create(controller, template:GetClass(), controller)
    local handle = util.handle(entry)
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
        handle = handle,
        text = text,
        button = util.findInTree(entry, "WBP_PalInvisibleButton"),
        pressed = false,
    }
end

-- The pause menu creates a new ESC menu when it is opened, so the entry is checked once per opening.
function menu.tick(now)
    local pauseMenu = activePauseMenu()
    if not pauseMenu then
        entryChecked = false
        return
    end
    if not entryChecked and now >= nextEscCheck then
        nextEscCheck = now + ESC_CHECK_INTERVAL
        local esc = util.findInTree(pauseMenu.object, isEscMenu)
        if esc then
            local address = esc:GetAddress()
            if not (escEntry and escEntry.escAddress == address and attached(escEntry.handle)) then
                escEntry = injectEntry(esc)
                if escEntry then
                    escEntry.escAddress = address
                end
            end
            entryChecked = escEntry ~= nil
        end
    end
    if not escEntry or not attached(escEntry.handle) then
        return
    end
    if escEntry.text and escEntry.text:GetText():ToString() ~= ENTRY_LABEL then
        escEntry.text:SetText(FText(ENTRY_LABEL))
    end
    -- The button lives in the entry's own widget tree, so it is safe to use while the entry is attached.
    if escEntry.button then
        local pressed = escEntry.button:IsPressed()
        if pressed and not escEntry.pressed and not isOpen then
            menu.open()
        end
        escEntry.pressed = pressed
    end
end

return menu

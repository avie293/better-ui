local util = require("util")
local settings = require("settings")
local hud = require("hud")
local UEHelpers = require("UEHelpers")

local valid = util.valid

local ESC_MENU = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C"
local IN_GAME_MENU = "/Game/Pal/Blueprint/UI/InGameMainMenu/WBP_InGameMainMenu.WBP_InGameMainMenu_C"
local ENTRY_LABEL = "HUD Layout"

local WINDOW_WIDTH, WINDOW_HEIGHT = 900, 600
local FRAME_MS = 16
local REPEAT_DELAY, REPEAT_INTERVAL = 0.45, 0.07
local OPEN_DELAY = 0.15

local VISIBLE, COLLAPSED = 0, 1
local FILL = { SizeRule = 1, Value = 1 }
local ALIGN_FILL, ALIGN_CENTER = 0, 2

local COLOR = {
    window = { 0.03, 0.035, 0.05, 0.95 },
    button = { 0.11, 0.13, 0.17, 1 },
    hover = { 0.17, 0.2, 0.26, 1 },
    active = { 0.13, 0.42, 0.6, 1 },
    activeHover = { 0.17, 0.5, 0.7, 1 },
    text = { 0.92, 0.94, 0.97, 1 },
    dim = { 0.55, 0.58, 0.64, 1 },
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
local looping = false
local openAt

local escMenu
local escEntry
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

local function addTo(box, widget, padding, fill)
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
    slot:SetVerticalAlignment(ALIGN_FILL)
    return slot
end

local function margin(left, top, right, bottom)
    return { Left = left, Top = top, Right = right, Bottom = bottom }
end

-- The engine's button brush cannot be restyled from Lua, so the button is kept invisible and a border
-- inside it draws the background. Hover and press states are polled every frame.
local function makeButton(label, action, options)
    options = options or {}
    local button = construct("Button")
    button:SetBackgroundColor(linear(COLOR.transparent))
    local border = construct("Border")
    border:SetBrushColor(linear(COLOR.button))
    border:SetPadding(margin(10, 5, 10, 5))
    border:SetHorizontalAlignment(ALIGN_CENTER)
    border:SetVerticalAlignment(ALIGN_CENTER)
    local text = makeText(label, options.size or 15)
    border:AddChild(text)
    local slot = button:AddChild(border)
    slot:SetPadding(margin(0, 0, 0, 0))
    slot:SetHorizontalAlignment(ALIGN_FILL)
    slot:SetVerticalAlignment(ALIGN_FILL)

    local clickable = {
        button = button,
        border = border,
        text = text,
        action = action,
        repeatable = options.repeatable,
        active = false,
    }
    clickables[#clickables + 1] = clickable
    return clickable, sized(button, options.width, options.height or 34)
end

local function setActive(clickable, active)
    clickable.active = active
    clickable.shownColor = nil
end

local function makeRow(parent, label)
    local row = construct("HorizontalBox")
    addTo(row, sized(makeText(label, 15, COLOR.dim), 150), margin(0, 0, 8, 0))
    local slot = addTo(parent, row, margin(0, 3, 0, 3))
    slot:SetVerticalAlignment(ALIGN_CENTER)
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
    addTo(row, sized(value, 110), margin(4, 6, 4, 0))
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
        end, { size = 14, height = 30 })
        clickable.border:SetHorizontalAlignment(1)
        controls.elements[definition.id] = clickable
        local slot = list:AddChild(widget)
        slot:SetPadding(margin(0, 0, 6, 3))
    end
    addTo(content, sized(list, 290), margin(0, 0, 18, 0))

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
    if not valid(window) then
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

local function frame()
    if not isOpen then
        return
    end
    if not valid(window) or not window:IsInViewport() then
        isOpen = false
        return
    end
    local now = os.clock()
    for i = 1, #clickables do
        if not isOpen then
            return
        end
        pollClickable(clickables[i], now)
    end
    -- Keep auto elements visible while they are being edited.
    hud.reveal(selected, 0.2)
end

local function startFrameLoop()
    if looping then
        return
    end
    looping = true
    local queued = false
    LoopAsync(FRAME_MS, function()
        if not isOpen then
            looping = false
            return true
        end
        if not queued then
            queued = true
            ExecuteInGameThread(function()
                queued = false
                local ok, err = pcall(frame)
                if not ok then
                    util.warnOnce("menu:" .. tostring(err), "Error in the settings window: " .. tostring(err))
                end
            end)
        end
        return false
    end)
end

function menu.open()
    local controller = UEHelpers.GetPlayerController()
    if not valid(controller) then
        return
    end
    if not valid(window) then
        buildWindow(controller)
    end
    menu.refreshWindow()
    if not window:IsInViewport() then
        window:AddToViewport(500)
    end
    controller.bShowMouseCursor = true
    library:SetInputMode_UIOnlyEx(controller, window, 0, false)
    isOpen = true
    startFrameLoop()
end

function menu.close()
    if not isOpen then
        return
    end
    isOpen = false
    if valid(window) then
        window:RemoveFromParent()
    end
    local controller = UEHelpers.GetPlayerController()
    if valid(controller) then
        library:SetInputMode_GameOnly(controller, false)
        controller.bShowMouseCursor = false
    end
    settings.save()
end

function menu.isOpen()
    return isOpen
end

-- Pause menu entry ----------------------------------------------------------------------------

local function injectEntry(esc)
    local list = util.findInTree(esc, "VerticalBox_91")
    local template = util.findInTree(esc, "WBP_MenuESC_Button_Tips")
    if not list or not template then
        util.warnOnce("esc", "Could not add the HUD Layout entry to the pause menu")
        return nil
    end
    local controller = UEHelpers.GetPlayerController()
    library = library or StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local entry = library:Create(controller, template:GetClass(), controller)
    local slot = list:AddChildToVerticalBox(entry)
    pcall(function()
        slot:SetPadding(template.Slot.Padding)
    end)
    local text = util.findInTree(entry, "Text_Main")
    if text and not gameFont then
        pcall(function()
            local font = text.Font
            gameFont = { FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName }
        end)
    end
    return {
        widget = entry,
        text = text,
        button = util.findInTree(entry, "WBP_PalInvisibleButton"),
        pressed = false,
    }
end

local function onEntryClicked(now)
    -- Close the pause menu first so the HUD can be seen while editing.
    local inGameMenu = util.findAttached(IN_GAME_MENU)
    if inGameMenu then
        local ok, err = pcall(function()
            inGameMenu:DeactivateWidget()
        end)
        if not ok then
            util.warnOnce("deactivate", "Could not close the pause menu: " .. tostring(err))
        end
    end
    -- Opening right away would be undone when the game restores its own input mode.
    openAt = now + OPEN_DELAY
end

function menu.tick(now)
    if openAt and now >= openAt then
        openAt = nil
        menu.open()
    end

    if now >= nextEscCheck then
        nextEscCheck = now + 1
        if not valid(escMenu) then
            escMenu = util.findAttached(ESC_MENU)
        end
        if valid(escMenu) and (not escEntry or not valid(escEntry.widget)) then
            escEntry = injectEntry(escMenu)
        end
        -- The button resets its label when the pause menu is rebuilt.
        if escEntry and escEntry.text and escEntry.text:GetText():ToString() ~= ENTRY_LABEL then
            escEntry.text:SetText(FText(ENTRY_LABEL))
        end
    end

    if escEntry and valid(escEntry.button) then
        local pressed = escEntry.button:IsPressed()
        if pressed and not escEntry.pressed then
            onEntryClicked(now)
        end
        escEntry.pressed = pressed
    end
end

return menu

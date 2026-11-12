local ELEMENTS = require("elements")

local MOD_NAME = "CleanPalUI"
local TICK_MS = 100
local REBIND_INTERVAL = 1.0
local ENFORCE_INTERVAL = 1.0
local PROGRESS_EPSILON = 0.001
local HOTKEY_DEBOUNCE = 0.3

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, message))
end

-- Paths ---------------------------------------------------------------------------------------

local function scriptDir()
    local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("/", "\\")
    return source:match("^(.*\\)") or ""
end

local SCRIPT_DIR = scriptDir()
local LOCAL_APP_DATA = os.getenv("LOCALAPPDATA")
-- Palworld's own config folder: it exists for every player and is left alone by mod updates.
local CONFIG_DIR = LOCAL_APP_DATA and (LOCAL_APP_DATA .. "\\Pal\\Saved\\Config\\") or SCRIPT_DIR
local CONFIG_PATH = CONFIG_DIR .. "CleanPalUI.lua"
local STATE_PATH = CONFIG_DIR .. "CleanPalUI.state"

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("a")
    file:close()
    return content
end

local function writeFile(path, content)
    local file = io.open(path, "wb")
    if not file then
        return false
    end
    file:write(content)
    file:close()
    return true
end

-- Config --------------------------------------------------------------------------------------

local function evaluate(source, name)
    local chunk, err = load(source, "=" .. name, "t", {})
    if not chunk then
        return nil, err
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, result
    end
    if type(result) ~= "table" then
        return nil, "the file must return a table"
    end
    return result
end

local function loadConfig()
    local defaultSource = readFile(SCRIPT_DIR .. "default_config.lua")
    local defaults = defaultSource and evaluate(defaultSource, "default_config") or require("default_config")

    local source = readFile(CONFIG_PATH)
    if not source then
        if defaultSource and writeFile(CONFIG_PATH, defaultSource) then
            log("Created " .. CONFIG_PATH)
        end
        return defaults
    end

    local config, err = evaluate(source, "CleanPalUI.lua")
    if not config then
        log("Could not load " .. CONFIG_PATH .. ": " .. tostring(err) .. ". Using the default config.")
        return defaults
    end

    for key, value in pairs(defaults) do
        if config[key] == nil then
            config[key] = value
        end
    end
    if type(config.hotkeys) ~= "table" then
        config.hotkeys = defaults.hotkeys
    end
    for name, hotkey in pairs(defaults.hotkeys) do
        if config.hotkeys[name] == nil then
            config.hotkeys[name] = hotkey
        end
    end
    if type(config.presets) ~= "table" then
        config.presets = defaults.presets
    end
    return config
end

local config = loadConfig()
local activePreset = readFile(STATE_PATH)
if not activePreset or not config.presets[activePreset] then
    activePreset = config.preset
end

-- Runtime state -------------------------------------------------------------------------------

local ELEMENT_BY_ID = {}
for _, element in ipairs(ELEMENTS) do
    ELEMENT_BY_ID[element.id] = element
end

local entries = {}
local roots = {}
local unresolved = {}
local warned = {}
local peeking = false
local peekUntil = 0
local nextRebind = 0
local nextEnforce = 0
local lastTick = os.clock()

local function warnOnce(key, message)
    if not warned[key] then
        warned[key] = true
        log(message)
    end
end

local function activeSettings()
    if peeking then
        return {}
    end
    return config.presets[activePreset] or {}
end

-- Widget access -------------------------------------------------------------------------------

local function valid(object)
    return object and object:IsValid() or false
end

-- FindAllOf walks every object in the game and takes over 20 ms, so it runs only once per class.
-- After that, new instances are reported by NotifyOnNewObject, which needs the class to be loaded.
local instances = {}

local function watchClass(classPath)
    if instances[classPath] then
        return true
    end
    if not valid(StaticFindObject(classPath)) then
        return false
    end
    local list = {}
    instances[classPath] = list
    NotifyOnNewObject(classPath, function(object)
        list[#list + 1] = object
    end)
    for _, object in ipairs(FindAllOf(classPath:match("%.([^%.]+)$")) or {}) do
        list[#list + 1] = object
    end
    return true
end

local function findRoot(classPath)
    if not watchClass(classPath) then
        return nil
    end
    local list = instances[classPath]
    for i = #list, 1, -1 do
        if not valid(list[i]) then
            table.remove(list, i)
        end
    end
    -- HUD widgets are owned by the game instance, so older instances can still be alive after a world change.
    -- The live one is the instance that is attached to the HUD layout.
    for _, widget in ipairs(list) do
        if valid(widget:GetParent()) and not widget:GetFullName():find("Default__", 1, true) then
            return widget
        end
    end
    return nil
end

local function nestedTree(widget)
    local ok, tree = pcall(function()
        return widget.WidgetTree
    end)
    if ok and valid(tree) then
        return tree
    end
    return nil
end

-- GetWidgetFromName does not find anything in Palworld's widgets, so the tree is walked by hand.
-- Only the user widget's own tree is searched; nested user widgets are separate steps in the path.
local function findInTree(userWidget, name)
    local tree = nestedTree(userWidget)
    if not tree then
        return nil
    end
    local queue = { tree.RootWidget }
    local head = 1
    while queue[head] do
        local widget = queue[head]
        queue[head] = false
        head = head + 1
        if valid(widget) then
            if widget:GetFName():ToString() == name then
                return widget
            end
            if not nestedTree(widget) then
                -- Widgets without children return a placeholder object for Slots that has no length.
                local ok, slots, count = pcall(function()
                    local value = widget.Slots
                    return value, #value
                end)
                if ok then
                    for i = 1, count do
                        local slot = slots[i]
                        local content = valid(slot) and slot.Content
                        if valid(content) then
                            queue[#queue + 1] = content
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function resolve(root, path)
    local widget = root
    for i = 1, #path do
        widget = findInTree(widget, path[i])
        if not widget then
            return nil
        end
    end
    return widget
end

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

-- Applying settings ---------------------------------------------------------------------------

local function multiply(color, factors)
    return {
        R = color.R * (factors[1] or 1),
        G = color.G * (factors[2] or 1),
        B = color.B * (factors[3] or 1),
        A = color.A * (factors[4] or 1),
    }
end

local function applyStatic(entry)
    local widget, settings, original = entry.widget, entry.settings, entry.original
    local scale = settings.scale or 1

    widget:SetRenderScale({ X = original.sx * scale, Y = original.sy * scale })
    widget:SetRenderTranslation({ X = original.tx + (settings.x or 0), Y = original.ty + (settings.y or 0) })

    if settings.tint or entry.tinted then
        if original.color then
            widget:SetColorAndOpacity(settings.tint and multiply(original.color, settings.tint) or original.color)
            entry.tinted = settings.tint ~= nil
        else
            warnOnce("tint:" .. entry.id, "tint is not supported for '" .. entry.id .. "'")
        end
    end

    local bar = entry.bar
    if (settings.bar_color or entry.barColored) and valid(bar) then
        if entry.originalBarColor then
            local c = settings.bar_color
            bar:SetFillColorAndOpacity(c and { R = c[1] or 1, G = c[2] or 1, B = c[3] or 1, A = c[4] or 1 }
                or entry.originalBarColor)
            entry.barColored = settings.bar_color ~= nil
        else
            warnOnce("bar:" .. entry.id, "bar_color is not supported for '" .. entry.id .. "'")
        end
    elseif settings.bar_color then
        warnOnce("bar:" .. entry.id, "bar_color is not supported for '" .. entry.id .. "'")
    end
end

local function restore(entry)
    if not valid(entry.widget) then
        return
    end
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

local function rootFor(classPath, searched)
    local root = roots[classPath]
    if valid(root) then
        return root
    end
    if searched[classPath] then
        return nil
    end
    searched[classPath] = true
    root = findRoot(classPath)
    roots[classPath] = root
    if root and classPath == ELEMENT_BY_ID.hud.root then
        log("Attached to the HUD, preset: " .. activePreset)
    end
    return root
end

local function createEntry(element, settings, searched)
    local root = rootFor(element.root, searched)
    if not root then
        return nil
    end
    -- Widgets that are missing in this HUD instance are only looked up again once the HUD is recreated.
    if unresolved[element.id] == root then
        return nil
    end
    local widget = resolve(root, element.path)
    if not widget then
        unresolved[element.id] = root
        warnOnce("missing:" .. element.id, "Could not find the widget for '" .. element.id .. "'")
        return nil
    end

    local entry = {
        id = element.id,
        element = element,
        settings = settings,
        widget = widget,
        original = captureOriginal(widget),
        watches = {},
        visibleUntil = 0,
    }
    entry.current = entry.original.opacity
    entry.applied = entry.current

    for _, watch in ipairs(element.watch or {}) do
        local target = resolve(root, watch.path)
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
    local settingsById = activeSettings()
    local searched = {}
    for id, settings in pairs(settingsById) do
        local element = ELEMENT_BY_ID[id]
        if not element then
            warnOnce("unknown:" .. id, "Unknown element id '" .. tostring(id) .. "' in preset '" .. activePreset .. "'")
        elseif type(settings) == "table" and not entries[id] then
            local entry = createEntry(element, settings, searched)
            if entry then
                entries[id] = entry
                applyStatic(entry)
            end
        end
    end
end

local function applySettings()
    local settingsById = activeSettings()
    for id, entry in pairs(entries) do
        local settings = settingsById[id]
        if type(settings) == "table" then
            entry.settings = settings
            if valid(entry.widget) then
                applyStatic(entry)
            end
        else
            restore(entry)
            entries[id] = nil
        end
    end
    nextRebind = 0
end

-- Auto mode -----------------------------------------------------------------------------------

local function readWatch(watch)
    if watch.definition.progress then
        return watch.widget.Percent
    end
    return watch.widget:GetText():ToString()
end

local function updateAuto(entry, now)
    local settings = entry.settings
    local active = false
    for _, watch in ipairs(entry.watches) do
        if valid(watch.widget) then
            local value = readWatch(watch)
            local definition = watch.definition
            local below = definition.below and (settings.below or definition.below)
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
                    entry.visibleUntil = now + (settings.seconds or config.auto_seconds)
                end
            end
            watch.last = value
        end
    end
    return active or now < entry.visibleUntil
end

local function targetOpacity(entry, now)
    local settings = entry.settings
    local opacity = entry.original.opacity * (settings.opacity or 1)
    if settings.mode == "hide" then
        return 0
    end
    if settings.mode == "auto" and #entry.watches > 0 then
        return updateAuto(entry, now) and opacity or 0
    end
    return opacity
end

-- Main loop -----------------------------------------------------------------------------------

local function tick()
    local now = os.clock()
    local dt = now - lastTick
    lastTick = now

    if peeking and config.peek_seconds > 0 and now >= peekUntil then
        peeking = false
        applySettings()
    end

    local stale = false
    for id, entry in pairs(entries) do
        if not valid(entry.widget) then
            entries[id] = nil
            stale = true
        end
    end
    if stale then
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

    local fade = config.fade_seconds
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

local tickQueued = false

local function safeTick()
    tickQueued = false
    local ok, err = pcall(tick)
    if not ok then
        warnOnce("tick:" .. tostring(err), "Error while updating the HUD: " .. tostring(err))
    end
end

LoopAsync(TICK_MS, function()
    -- Skip queueing while the game thread is busy, e.g. on loading screens.
    if not tickQueued then
        tickQueued = true
        ExecuteInGameThread(safeTick)
    end
    return false
end)

-- Hotkeys -------------------------------------------------------------------------------------

local function nextPreset()
    local order = config.preset_order
    local index = 0
    for i, name in ipairs(order) do
        if name == activePreset then
            index = i
        end
    end
    for offset = 1, #order do
        local name = order[(index + offset - 1) % #order + 1]
        if config.presets[name] then
            activePreset = name
            break
        end
    end
    writeFile(STATE_PATH, activePreset)
    peeking = false
    applySettings()
    log("Preset: " .. activePreset)
end

local function togglePeek()
    if config.peek_seconds > 0 then
        peeking = true
        peekUntil = os.clock() + config.peek_seconds
    else
        peeking = not peeking
    end
    applySettings()
end

local function reload()
    config = loadConfig()
    if not config.presets[activePreset] then
        activePreset = config.preset
    end
    warned = {}
    unresolved = {}
    applySettings()
    log("Config reloaded, preset: " .. activePreset)
end

local function registerHotkey(name, action)
    local hotkey = config.hotkeys[name]
    if type(hotkey) ~= "table" or not hotkey.key or hotkey.key == "" then
        return
    end
    local key = Key[hotkey.key]
    if not key then
        log("Unknown key '" .. tostring(hotkey.key) .. "' for hotkey '" .. name .. "'")
        return
    end
    local modifiers = {}
    if hotkey.ctrl then
        modifiers[#modifiers + 1] = ModifierKey.CONTROL
    end
    if hotkey.shift then
        modifiers[#modifiers + 1] = ModifierKey.SHIFT
    end
    if hotkey.alt then
        modifiers[#modifiers + 1] = ModifierKey.ALT
    end
    local lastPress = 0
    local callback = function()
        -- A single key press can be reported more than once.
        local now = os.clock()
        if now - lastPress < HOTKEY_DEBOUNCE then
            return
        end
        lastPress = now
        ExecuteInGameThread(function()
            local ok, err = pcall(action)
            if not ok then
                log("Error in hotkey '" .. name .. "': " .. tostring(err))
            end
        end)
    end
    if #modifiers > 0 then
        RegisterKeyBind(key, modifiers, callback)
    else
        RegisterKeyBind(key, callback)
    end
end

registerHotkey("next_preset", nextPreset)
registerHotkey("peek", togglePeek)
registerHotkey("reload", reload)

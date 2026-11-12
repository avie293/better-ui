local util = require("util")

local SAVE_DELAY = 0.5

local function scriptDir()
    local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("/", "\\")
    return source:match("^(.*\\)") or ""
end

local SCRIPT_DIR = scriptDir()
local LOCAL_APP_DATA = os.getenv("LOCALAPPDATA")
-- Palworld's own config folder: it exists for every player and is left alone by mod updates.
local CONFIG_PATH = (LOCAL_APP_DATA and (LOCAL_APP_DATA .. "\\Pal\\Saved\\Config\\") or SCRIPT_DIR) .. "BetterUI.lua"

local HEADER = [[
-- Better UI settings. Use the "HUD Layout" entry in the pause menu to change them in game.
-- This file is rewritten by the mod; delete it to restore the defaults.

]]

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

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copy(item)
    end
    return result
end

local function isArray(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count == #value
end

local function serialize(value, indent)
    local kind = type(value)
    if kind == "string" then
        return string.format("%q", value)
    elseif kind == "number" then
        return value == math.floor(value) and string.format("%d", value) or string.format("%.3f", value)
    elseif kind ~= "table" then
        return tostring(value)
    end
    if next(value) == nil then
        return "{}"
    end
    if isArray(value) then
        local items = {}
        for i, item in ipairs(value) do
            items[i] = serialize(item, indent)
        end
        return "{ " .. table.concat(items, ", ") .. " }"
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local inner = indent .. "    "
    local lines = {}
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format("%s%s = %s,", inner, key, serialize(value[key], inner))
    end
    return "{\n" .. table.concat(lines, "\n") .. "\n" .. indent .. "}"
end

local DEFAULTS = require("default_config")

local settings = {}
local config
local saveAt

function settings.load()
    config = copy(DEFAULTS)
    local source = readFile(CONFIG_PATH)
    if not source then
        return
    end
    local loaded, err = evaluate(source, "BetterUI.lua")
    if not loaded then
        util.log("Could not load " .. CONFIG_PATH .. ": " .. tostring(err) .. ". Using the defaults.")
        return
    end
    for key, value in pairs(loaded) do
        local default = DEFAULTS[key]
        if default ~= nil and type(value) == type(default) then
            if key == "theme" then
                for field, fieldDefault in pairs(default) do
                    if type(value[field]) ~= type(fieldDefault) then
                        value[field] = fieldDefault
                    end
                end
            end
            config[key] = value
        end
    end
    for name, preset in pairs(DEFAULTS.presets) do
        if type(config.presets[name]) ~= "table" then
            config.presets[name] = copy(preset)
        end
    end
    if not config.presets[config.preset] then
        config.preset = DEFAULTS.preset
    end
end

function settings.save()
    saveAt = nil
    if not writeFile(CONFIG_PATH, HEADER .. "return " .. serialize(config, "") .. "\n") then
        util.warnOnce("save", "Could not write " .. CONFIG_PATH)
    end
end

function settings.markDirty()
    saveAt = os.clock() + SAVE_DELAY
end

function settings.update(now)
    if saveAt and now >= saveAt then
        settings.save()
    end
end

function settings.get(key)
    return config[key]
end

function settings.set(key, value)
    config[key] = value
    settings.markDirty()
end

function settings.setTheme(field, value)
    config.theme[field] = value
    settings.markDirty()
end

function settings.presetNames()
    return config.preset_order
end

function settings.activePreset()
    return config.preset
end

function settings.isEditable()
    return config.preset ~= "vanilla"
end

function settings.setPreset(name)
    if config.presets[name] then
        config.preset = name
        settings.markDirty()
    end
end

function settings.active()
    return config.presets[config.preset] or {}
end

function settings.element(id)
    return settings.active()[id]
end

function settings.setValue(id, key, value)
    local preset = settings.active()
    local element = preset[id]
    if not element then
        element = {}
        preset[id] = element
    end
    element[key] = value
    if next(element) == nil then
        preset[id] = nil
    end
    settings.markDirty()
end

function settings.resetElement(id)
    local default = DEFAULTS.presets[config.preset]
    settings.active()[id] = default and copy(default[id]) or nil
    settings.markDirty()
end

function settings.resetPreset()
    local default = DEFAULTS.presets[config.preset]
    config.presets[config.preset] = default and copy(default) or {}
    settings.markDirty()
end

return settings

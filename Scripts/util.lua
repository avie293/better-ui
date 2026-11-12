local util = {}

function util.log(message)
    print(string.format("[CleanPalUI] %s\n", message))
end

local warned = {}

function util.warnOnce(key, message)
    if not warned[key] then
        warned[key] = true
        util.log(message)
    end
end

function util.valid(object)
    return object and object:IsValid() or false
end

local valid = util.valid

function util.nestedTree(widget)
    local ok, tree = pcall(function()
        return widget.WidgetTree
    end)
    if ok and valid(tree) then
        return tree
    end
    return nil
end

-- GetWidgetFromName does not find anything in Palworld's widgets, so the tree is walked by hand.
-- Only the user widget's own tree is searched; nested user widgets are separate steps in a path.
-- The match is either a widget name or a function that receives each widget.
function util.findInTree(userWidget, match)
    local matches = match
    if type(match) == "string" then
        matches = function(widget)
            return widget:GetFName():ToString() == match
        end
    end
    local tree = util.nestedTree(userWidget)
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
            if matches(widget) then
                return widget
            end
            if not util.nestedTree(widget) then
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

function util.resolve(root, path)
    local widget = root
    for i = 1, #path do
        widget = util.findInTree(widget, path[i])
        if not widget then
            return nil
        end
    end
    return widget
end

-- Lua keeps raw pointers to objects. Once the game frees an object, even IsValid reads freed memory and can
-- crash, so objects that may be destroyed are kept as handles and looked up by path before every use.
function util.alive(handle)
    if not handle then
        return false
    end
    local found = StaticFindObject(handle.path)
    return found ~= nil and found:IsValid() and found:GetAddress() == handle.address
end

function util.handle(object)
    local handle = {
        object = object,
        path = object:GetFullName():match("^%S+%s+(.+)$"),
        address = object:GetAddress(),
    }
    if not util.alive(handle) then
        util.warnOnce("handle:" .. tostring(handle.path), "Could not look up " .. tostring(handle.path))
    end
    return handle
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
        list[#list + 1] = util.handle(object)
    end)
    for _, object in ipairs(FindAllOf(classPath:match("%.([^%.]+)$")) or {}) do
        if object:IsValid() then
            list[#list + 1] = util.handle(object)
        end
    end
    return true
end

-- Palworld's widgets are owned by the game instance, so older instances can still be alive after a world
-- change. The live one is the instance that is attached to a parent widget. Returns a handle.
function util.findAttached(classPath)
    if not watchClass(classPath) then
        return nil
    end
    local list = instances[classPath]
    for i = #list, 1, -1 do
        if not util.alive(list[i]) then
            table.remove(list, i)
        end
    end
    for _, handle in ipairs(list) do
        if not handle.path:find("Default__", 1, true) and valid(handle.object:GetParent()) then
            return handle
        end
    end
    return nil
end

return util

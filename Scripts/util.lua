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

function util.className(object)
    return object:GetClass():GetFName():ToString()
end

function util.isClass(name)
    return function(widget)
        return util.className(widget) == name
    end
end

-- Checks through a live panel whether a widget is still in it, without touching the widget itself.
function util.hasChild(list, address)
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

return util

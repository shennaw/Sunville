-- ButtonManager.lua
-- Generic button management system for the game

local ButtonManager = {}
ButtonManager.__index = ButtonManager

function ButtonManager.new()
    local manager = {
        buttons = {},
        buttonTypes = {},
        buttonStates = {},
        defaultScale = 1 -- Will be updated dynamically
    }
    
    setmetatable(manager, ButtonManager)
    return manager
end

-- Button types
ButtonManager.TYPE_SELECTION = "selection"
ButtonManager.TYPE_DRAGGING = "dragging"
ButtonManager.TYPE_ACTION = "action"

-- Button states
ButtonManager.STATE_VISIBLE = "visible"
ButtonManager.STATE_HIDDEN = "hidden"
ButtonManager.STATE_DISABLED = "disabled"

function ButtonManager:addButton(id, config)
    local button = {
        id = id,
        type = config.type or ButtonManager.TYPE_ACTION,
        x = config.x or 0,
        y = config.y or 0,
        width = config.width or 100,
        height = config.height or 50,
        icon = config.icon,
        showHand = config.showHand or false,
        action = config.action,
        state = ButtonManager.STATE_VISIBLE,
        visible = config.visible or true,
        scale = config.scale or self.defaultScale
    }
    
    self.buttons[id] = button
    return button
end

function ButtonManager:setButtonState(id, state)
    if self.buttons[id] then
        self.buttons[id].state = state
    end
end

function ButtonManager:setButtonVisibility(id, visible)
    if self.buttons[id] then
        self.buttons[id].visible = visible
    end
end

function ButtonManager:getButton(id)
    return self.buttons[id]
end

function ButtonManager:getButtonAtPosition(x, y)
    for id, button in pairs(self.buttons) do
        if button.visible and button.state == ButtonManager.STATE_VISIBLE then
            if x >= button.x and x <= button.x + button.width and
               y >= button.y and y <= button.y + button.height then
                return button
            end
        end
    end
    return nil
end

function ButtonManager:handleClick(x, y)
    local button = self:getButtonAtPosition(x, y)
    if button and button.action then
        button.action()
        return button
    end
    return nil
end

function ButtonManager:clearButtons()
    self.buttons = {}
end

function ButtonManager:clearButtonsByType(buttonType)
    for id, button in pairs(self.buttons) do
        if button.type == buttonType then
            self.buttons[id] = nil
        end
    end
end

-- Factory methods for common button configurations
function ButtonManager:createSelectionButtons(screenW, screenH, labelImages, icons, actions, mapScale)
    self:clearButtonsByType(ButtonManager.TYPE_SELECTION)
    
    local scale = mapScale or self.defaultScale
    local btnHeight = labelImages.left and (labelImages.left:getHeight() * scale) or 80
    local btnY = screenH - btnHeight - 8
    local leftW = math.floor(screenW * 0.5) - 16 -- Reduced width to create gap
    
    -- Move button (left half)
    self:addButton("select_move", {
        type = ButtonManager.TYPE_SELECTION,
        x = 8,
        y = btnY,
        width = leftW,
        height = btnHeight,
        icon = nil,
        showHand = true,
        action = actions.move,
        scale = scale
    })
    
    -- Cancel button (right half)
    self:addButton("select_cancel", {
        type = ButtonManager.TYPE_SELECTION,
        x = screenW - leftW - 8,
        y = btnY,
        width = leftW,
        height = btnHeight,
        icon = icons.cancel,
        showHand = false,
        action = actions.cancel,
        scale = scale
    })
end

function ButtonManager:createDraggingButtons(screenW, screenH, labelImages, icons, actions, mapScale)
    self:clearButtonsByType(ButtonManager.TYPE_DRAGGING)
    
    local scale = mapScale or self.defaultScale
    local btnHeight = labelImages.left and (labelImages.left:getHeight() * scale) or 80
    local btnY = screenH - btnHeight - 8
    local leftW = math.floor(screenW * 0.5) - 16 -- Reduced width to create gap
    
    -- Accept button (left half)
    self:addButton("drag_accept", {
        type = ButtonManager.TYPE_DRAGGING,
        x = 8,
        y = btnY,
        width = leftW,
        height = btnHeight,
        icon = icons.confirm,
        showHand = false,
        action = actions.accept,
        scale = scale
    })
    
    -- Cancel button (right half)
    self:addButton("drag_cancel", {
        type = ButtonManager.TYPE_DRAGGING,
        x = screenW - leftW - 8,
        y = btnY,
        width = leftW,
        height = btnHeight,
        icon = icons.cancel,
        showHand = false,
        action = actions.cancel,
        scale = scale
    })
end

function ButtonManager:drawButtons(labelImages, handImage)
    for id, button in pairs(self.buttons) do
        if button.visible and button.state == ButtonManager.STATE_VISIBLE then
            self:drawButton(button, labelImages, handImage)
        end
    end
end

function ButtonManager:drawButton(button, labelImages, handImage)
    if not (labelImages.left and labelImages.middle and labelImages.right) then 
        return 
    end
    
    local scale = button.scale
    local leftW = math.floor(labelImages.left:getWidth() * scale)
    local rightW = math.floor(labelImages.right:getWidth() * scale)
    local midW = math.max(0, button.width - leftW - rightW)
    
    -- Draw left cap
    love.graphics.draw(labelImages.left, button.x, button.y, 0, scale, scale)
    
    -- Draw middle section (tiled to fill the space)
    if midW > 0 then
        local tileW = math.floor(labelImages.middle:getWidth() * scale)
        if tileW > 0 then
            local tiles = math.ceil(midW / tileW)
            for i = 0, tiles - 1 do
                local dx = button.x + leftW + i * tileW
                -- Clip the middle tile if it extends beyond the button width
                local clipW = math.min(tileW, midW - i * tileW)
                if clipW > 0 then
                    local quad = love.graphics.newQuad(0, 0, 
                        math.min(labelImages.middle:getWidth(), clipW / scale), 
                        labelImages.middle:getHeight(), 
                        labelImages.middle:getWidth(), labelImages.middle:getHeight())
                    love.graphics.draw(labelImages.middle, quad, dx, button.y, 0, scale, scale)
                end
            end
        end
    end
    
    -- Draw right cap - ensure it's positioned exactly at the end
    local rightX = button.x + button.width - rightW
    love.graphics.draw(labelImages.right, rightX, button.y, 0, scale, scale)
    
    -- Draw icon
    if button.icon then
        local iconX = button.x + button.width * 0.5 - (button.icon:getWidth() * scale) * 0.5
        local iconY = button.y + (button.height - button.icon:getHeight() * scale) * 0.5
        love.graphics.draw(button.icon, iconX, iconY, 0, scale, scale)
    end
    
    -- Draw hand icon if requested
    if button.showHand and handImage then
        local handX = button.x + button.width * 0.5 - handImage:getWidth() * scale * 0.5
        local handY = button.y + (button.height - handImage:getHeight() * scale) * 0.5
        love.graphics.draw(handImage, handX, handY, 0, scale, scale)
    end
end

return ButtonManager

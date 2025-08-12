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
        actionType = config.actionType, -- Add action type for identification
        state = config.state or ButtonManager.STATE_VISIBLE,
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
    if button then
        -- Check if this is an axe action that should be handled externally
        if button.actionType == "axe" then
            -- Don't call button.action() for axe actions - let main.lua handle it
            return button
        elseif button.action then
            button.action()
            return button
        end
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
    local baseHeight = labelImages.left and (labelImages.left:getHeight() * scale) or 80
    local btnHeight = baseHeight * 2  -- 2x button height
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
    local baseHeight = labelImages.left and (labelImages.left:getHeight() * scale) or 80
    local btnHeight = baseHeight * 2  -- 2x button height
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
    
    -- Cancel button (right half) - always on the right
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

function ButtonManager:createActionButtons(screenW, screenH, labelImages, icons, actions, mapScale)
    self:clearButtonsByType(ButtonManager.TYPE_ACTION)
    
    local scale = mapScale or self.defaultScale
    local baseHeight = labelImages.left and (labelImages.left:getHeight() * scale) or 80
    local btnHeight = baseHeight * 2  -- 2x button height
    local btnY = screenH - btnHeight - 8
    
    -- Count the number of actions to determine button layout
    local actionCount = 0
    local actionList = {}
    local cancelAction = nil
    
    -- Separate cancel action from others to ensure it's always on the right
    for action, callback in pairs(actions) do
        actionCount = actionCount + 1
        if action == "cancel" then
            cancelAction = {name = action, callback = callback}
        else
            table.insert(actionList, {name = action, callback = callback})
        end
    end
    
    -- Add cancel action at the end (rightmost position)
    if cancelAction then
        table.insert(actionList, cancelAction)
    end
    
    if actionCount == 0 then return end
    
    -- Calculate button width based on number of actions
    local totalWidth = screenW - 16 -- 8px margin on each side
    local buttonGap = 8
    local btnWidth = math.floor((totalWidth - (actionCount - 1) * buttonGap) / actionCount)
    
    for i, actionData in ipairs(actionList) do
        local btnX = 8 + (i - 1) * (btnWidth + buttonGap)
        local actionName = actionData.name
        local icon = nil
        local showHand = false
        
        -- Set icon and hand based on action type
        if actionName == "move" then
            showHand = true
        elseif actionName == "axe" then
            icon = icons.axe or icons.confirm -- use axe.png icon
        elseif actionName == "pickaxe" then
            icon = icons.pickaxe or icons.confirm
        elseif actionName == "cancel" then
            icon = icons.cancel
        end
        
        self:addButton("action_" .. actionName, {
            type = ButtonManager.TYPE_ACTION,
            x = btnX,
            y = btnY,
            width = btnWidth,
            height = btnHeight,
            icon = icon,
            showHand = showHand,
            action = actionData.callback,
            actionType = actionName, -- Include action type
            scale = scale
        })
    end
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
    local scaleY = scale * 2  -- 2x vertical scale to match button height
    local leftW = math.floor(labelImages.left:getWidth() * scale)
    local rightW = math.floor(labelImages.right:getWidth() * scale)
    local midW = math.max(0, button.width - leftW - rightW)
    
    -- Draw left cap with 2x height
    love.graphics.draw(labelImages.left, button.x, button.y, 0, scale, scaleY)
    
    -- Draw middle section (tiled to fill the space) with 2x height
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
                    love.graphics.draw(labelImages.middle, quad, dx, button.y, 0, scale, scaleY)
                end
            end
        end
    end
    
    -- Draw right cap - ensure it's positioned exactly at the end, with 2x height
    local rightX = button.x + button.width - rightW
    love.graphics.draw(labelImages.right, rightX, button.y, 0, scale, scaleY)
    
    -- Draw icon (scale icons to match button proportions)
    if button.icon then
        local iconScale = scale * 1.5  -- Scale icons slightly larger for taller buttons
        local iconX = button.x + button.width * 0.5 - (button.icon:getWidth() * iconScale) * 0.5
        local iconY = button.y + (button.height - button.icon:getHeight() * iconScale) * 0.5
        love.graphics.draw(button.icon, iconX, iconY, 0, iconScale, iconScale)
    end
    
    -- Draw hand icon if requested (scale hand icons to match button proportions)
    if button.showHand and handImage then
        local handScale = scale * 1.5  -- Scale hand icons slightly larger for taller buttons
        local handX = button.x + button.width * 0.5 - handImage:getWidth() * handScale * 0.5
        local handY = button.y + (button.height - handImage:getHeight() * handScale) * 0.5
        love.graphics.draw(handImage, handX, handY, 0, handScale, handScale)
    end
end

return ButtonManager

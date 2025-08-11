-- ActionableObject.lua
-- Unified class for any object that can be selected and have actions performed on it

local ActionableObject = {}
ActionableObject.__index = ActionableObject

-- Object types and their available actions
local OBJECT_TYPE_HOUSE = "house"
local OBJECT_TYPE_TREE = "tree"
local OBJECT_TYPE_ROCK = "rock"

local OBJECT_ACTIONS = {
    [OBJECT_TYPE_HOUSE] = {"move"},
    [OBJECT_TYPE_TREE] = {"axe", "water"},
    [OBJECT_TYPE_ROCK] = {"pickaxe"}
}

function ActionableObject.new(mapData, tileX, tileY, name, objectType)
    local obj = {
        -- Map data
        mapData = mapData,
        tileX = tileX or 0,
        tileY = tileY or 0,
        name = name or "Unknown",
        objectType = objectType or OBJECT_TYPE_HOUSE,
        
        -- Selection state
        isSelected = false,
        selectClickTileX = 0,
        selectClickTileY = 0,
        
        -- Drag state (only used if object supports dragging/moving)
        isDragging = false,
        dragOffsetX = 0,
        dragOffsetY = 0,
        dragAnchorDeltaX = 0,
        dragAnchorDeltaY = 0,
        dragDelayTimer = 0,
        
        -- Original position for canceling
        originalTileX = tileX or 0,
        originalTileY = tileY or 0,
        
        -- Selection corner animation
        selectionAnimTime = 0,
        selectionAnimDuration = 1.5, -- Full cycle duration in seconds
        selectionAnimOffset = 3, -- Maximum pixel offset for corners
        
        -- Validation (for draggable objects)
        previewPlacementValid = true,
        invalidPlacementReason = nil,
        
        -- Collision masks
        waterMask = nil,
        treeMask = nil,
        
        -- Action state
        currentAction = nil,
        actionInProgress = false
    }
    
    setmetatable(obj, ActionableObject)
    return obj
end

function ActionableObject:getObjectType()
    return self.objectType
end

function ActionableObject:getAvailableActions()
    return OBJECT_ACTIONS[self.objectType] or {}
end

function ActionableObject:canPerformAction(action)
    local actions = self:getAvailableActions()
    for _, availableAction in ipairs(actions) do
        if availableAction == action then
            return true
        end
    end
    return false
end

function ActionableObject:isDraggable()
    return self:canPerformAction("move")
end

function ActionableObject:setCollisionMasks(waterMask, treeMask)
    self.waterMask = waterMask
    self.treeMask = treeMask
end

function ActionableObject:getWidth()
    return self.mapData and self.mapData.width or 0
end

function ActionableObject:getHeight()
    return self.mapData and self.mapData.height or 0
end

function ActionableObject:getCurrentTileX()
    return self.tileX + self.dragOffsetX
end

function ActionableObject:getCurrentTileY()
    return self.tileY + self.dragOffsetY
end

function ActionableObject:isPointInside(tileX, tileY)
    local width = self:getWidth()
    local height = self:getHeight()
    return tileX >= self.tileX and tileX < self.tileX + width and 
           tileY >= self.tileY and tileY < self.tileY + height
end

function ActionableObject:select(tileX, tileY)
    if self.isDragging or self.actionInProgress then return false end
    
    self.isSelected = true
    self.selectClickTileX = tileX
    self.selectClickTileY = tileY
    self.isDragging = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.dragDelayTimer = 0
    self.currentAction = nil
    
    -- Calculate the offset from where we clicked on the object to its top-left corner (for dragging)
    self.dragAnchorDeltaX = tileX - self.tileX
    self.dragAnchorDeltaY = tileY - self.tileY
    
    return true
end

function ActionableObject:performAction(action, callback)
    if not self:canPerformAction(action) then
        print("Cannot perform action " .. action .. " on " .. self.objectType)
        return false
    end
    
    if action == "move" then
        return self:startDragging()
    elseif action == "axe" then
        return self:performAxeAction(callback)
    elseif action == "water" then
        return self:performWaterAction(callback)
    elseif action == "pickaxe" then
        return self:performPickaxeAction(callback)
    end
    
    return false
end

function ActionableObject:startDragging()
    if not self.isSelected or not self:isDraggable() then return false end
    
    self.isDragging = true
    self.isSelected = false
    self.originalTileX = self.tileX
    self.originalTileY = self.tileY
    self.dragDelayTimer = 0.1 -- 100ms delay
    self.currentAction = "move"
    
    return true
end

function ActionableObject:performAxeAction(callback)
    if self.objectType ~= OBJECT_TYPE_TREE then return false end
    
    self.actionInProgress = true
    self.currentAction = "axe"
    
    -- Simulate axing animation/delay
    print("Chopping down " .. self.name .. "...")
    
    -- After animation completes, remove the tree
    -- For now, we'll just call the callback immediately
    if callback then
        callback(self, "axe", true) -- success
    end
    
    return true
end

function ActionableObject:performWaterAction(callback)
    if self.objectType ~= OBJECT_TYPE_TREE then return false end
    
    self.actionInProgress = true
    self.currentAction = "water"
    
    print("Watering " .. self.name .. "...")
    
    -- After watering animation completes
    if callback then
        callback(self, "water", true) -- success
    end
    
    return true
end

function ActionableObject:performPickaxeAction(callback)
    if self.objectType ~= OBJECT_TYPE_ROCK then return false end
    
    self.actionInProgress = true
    self.currentAction = "pickaxe"
    
    print("Mining " .. self.name .. "...")
    
    -- After mining animation completes
    if callback then
        callback(self, "pickaxe", true) -- success
    end
    
    return true
end

function ActionableObject:updateDrag(dt)
    if self.dragDelayTimer > 0 then
        self.dragDelayTimer = self.dragDelayTimer - dt
    end
end

function ActionableObject:updateSelection(dt)
    -- Update selection corner animation when selected
    if self.isSelected then
        self.selectionAnimTime = self.selectionAnimTime + dt
        -- Keep animation time within bounds to prevent floating point precision issues
        if self.selectionAnimTime > self.selectionAnimDuration then
            self.selectionAnimTime = self.selectionAnimTime - self.selectionAnimDuration
        end
    else
        self.selectionAnimTime = 0
    end
end

function ActionableObject:getSelectionCornerOffset()
    if not self.isSelected then
        return 0
    end
    
    -- Create a smooth breathing animation using sine wave
    local progress = (self.selectionAnimTime / self.selectionAnimDuration) * 2 * math.pi
    local sineValue = math.sin(progress)
    
    -- Map sine wave (-1 to 1) to offset (0 to selectionAnimOffset)
    local offset = (sineValue + 1) * 0.5 * self.selectionAnimOffset
    
    return math.floor(offset) -- Return integer offset to avoid sub-pixel positioning
end

function ActionableObject:updatePosition(tileX, tileY, sceneWidth, sceneHeight)
    if not self.isDragging or self.dragDelayTimer > 0 then return end
    
    -- Use the drag anchor deltas to maintain relative position from initial click
    local desiredTopLeftX = tileX - self.dragAnchorDeltaX
    local desiredTopLeftY = tileY - self.dragAnchorDeltaY
    
    -- Clamp desired top-left within map bounds
    local maxX = sceneWidth - self:getWidth()
    local maxY = sceneHeight - self:getHeight()
    desiredTopLeftX = math.max(0, math.min(desiredTopLeftX, maxX))
    desiredTopLeftY = math.max(0, math.min(desiredTopLeftY, maxY))
    
    -- Convert to offsets from current committed top-left
    self.dragOffsetX = desiredTopLeftX - self.tileX
    self.dragOffsetY = desiredTopLeftY - self.tileY
    
    -- Validate placement
    self:validatePlacement(sceneWidth, sceneHeight, nil)
end

function ActionableObject:validatePlacement(sceneWidth, sceneHeight, gameStateManager)
    self.previewPlacementValid = true
    self.invalidPlacementReason = nil
    
    local finalX = self:getCurrentTileX()
    local finalY = self:getCurrentTileY()
    local width = self:getWidth()
    local height = self:getHeight()
    
    -- Check bounds
    if finalX < 0 or finalY < 0 or finalX + width > sceneWidth or finalY + height > sceneHeight then
        self.previewPlacementValid = false
        self.invalidPlacementReason = "Cannot place outside map bounds"
        return
    end
    
    -- Check water and tree collisions
    if self.waterMask then
        for row = 0, height - 1 do
            for col = 0, width - 1 do
                local checkX = finalX + col
                local checkY = finalY + row
                local overlapsWater = self.waterMask[checkY + 1] and self.waterMask[checkY + 1][checkX + 1]
                local overlapsTree = self.treeMask and self.treeMask[checkY + 1] and self.treeMask[checkY + 1][checkX + 1]
                
                if overlapsWater or overlapsTree then
                    self.previewPlacementValid = false
                    self.invalidPlacementReason = overlapsWater and "Cannot place on water" or "Cannot place on trees"
                    return
                end
            end
            if not self.previewPlacementValid then break end
        end
    end
    
    -- Check object intersection if gameStateManager is provided
    if gameStateManager then
        local intersects, otherObject = gameStateManager:checkObjectIntersection(self, finalX, finalY)
        if intersects then
            self.previewPlacementValid = false
            self.invalidPlacementReason = "Cannot place on top of " .. (otherObject.name or "another object")
            return
        end
    end
end

function ActionableObject:acceptPlacement()
    if not self.isDragging then return false end
    
    if self.previewPlacementValid then
        self.tileX = self.tileX + self.dragOffsetX
        self.tileY = self.tileY + self.dragOffsetY
    end
    
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.isDragging = false
    self.dragDelayTimer = 0
    self.currentAction = nil
    
    return true
end

function ActionableObject:cancelDragging()
    if not self.isDragging then return false end
    
    self.tileX = self.originalTileX
    self.tileY = self.originalTileY
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.isDragging = false
    self.dragDelayTimer = 0
    self.currentAction = nil
    
    return true
end

function ActionableObject:cancelSelection()
    if not self.isSelected then return false end
    
    self.isSelected = false
    self.dragDelayTimer = 0
    self.currentAction = nil
    
    return true
end

function ActionableObject:cancelAction()
    self.actionInProgress = false
    self.currentAction = nil
    return true
end

function ActionableObject:reset()
    self.isSelected = false
    self.isDragging = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.dragDelayTimer = 0
    self.previewPlacementValid = true
    self.invalidPlacementReason = nil
    self.actionInProgress = false
    self.currentAction = nil
end

return ActionableObject
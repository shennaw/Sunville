-- DraggableObject.lua
-- Generic class for any object that can be dragged in the game

local DraggableObject = {}
DraggableObject.__index = DraggableObject

function DraggableObject.new(mapData, tileX, tileY, name)
    local obj = {
        -- Map data
        mapData = mapData,
        tileX = tileX or 0,
        tileY = tileY or 0,
        name = name or "Unknown",
        
        -- Drag state
        isSelected = false,
        isDragging = false,
        dragOffsetX = 0,
        dragOffsetY = 0,
        dragAnchorDeltaX = 0,
        dragAnchorDeltaY = 0,
        dragDelayTimer = 0,
        
        -- Original position for canceling
        originalTileX = tileX or 0,
        originalTileY = tileY or 0,
        
        -- Selection state
        selectClickTileX = 0,
        selectClickTileY = 0,
        
        -- Selection corner animation
        selectionAnimTime = 0,
        selectionAnimDuration = 1.5, -- Full cycle duration in seconds
        selectionAnimOffset = 3, -- Maximum pixel offset for corners
        
        -- Validation
        previewPlacementValid = true,
        invalidPlacementReason = nil,
        
        -- Collision masks
        waterMask = nil,
        treeMask = nil
    }
    
    setmetatable(obj, DraggableObject)
    return obj
end

function DraggableObject:setCollisionMasks(waterMask, treeMask)
    self.waterMask = waterMask
    self.treeMask = treeMask
end

function DraggableObject:getWidth()
    return self.mapData and self.mapData.width or 0
end

function DraggableObject:getHeight()
    return self.mapData and self.mapData.height or 0
end

function DraggableObject:getCurrentTileX()
    return self.tileX + self.dragOffsetX
end

function DraggableObject:getCurrentTileY()
    return self.tileY + self.dragOffsetY
end

function DraggableObject:isPointInside(tileX, tileY)
    local width = self:getWidth()
    local height = self:getHeight()
    return tileX >= self.tileX and tileX < self.tileX + width and 
           tileY >= self.tileY and tileY < self.tileY + height
end

function DraggableObject:select(tileX, tileY)
    if self.isDragging then return false end
    
    self.isSelected = true
    self.selectClickTileX = tileX
    self.selectClickTileY = tileY
    self.isDragging = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.dragDelayTimer = 0
    
    -- Calculate the offset from where we clicked on the object to its top-left corner
    self.dragAnchorDeltaX = tileX - self.tileX
    self.dragAnchorDeltaY = tileY - self.tileY
    
    return true
end

function DraggableObject:startDragging()
    if not self.isSelected then return false end
    
    self.isDragging = true
    self.isSelected = false
    self.originalTileX = self.tileX
    self.originalTileY = self.tileY
    self.dragDelayTimer = 0.1 -- 100ms delay
    
    return true
end

function DraggableObject:updateDrag(dt)
    if self.dragDelayTimer > 0 then
        self.dragDelayTimer = self.dragDelayTimer - dt
    end
end

function DraggableObject:updateSelection(dt)
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

function DraggableObject:getSelectionCornerOffset()
    if not self.isSelected then
        return 0
    end
    
    -- Create a smooth breathing animation using sine wave
    local progress = (self.selectionAnimTime / self.selectionAnimDuration) * 2 * math.pi
    local sineValue = math.sin(progress)
    
    -- Map sine wave (-1 to 1) to offset (0 to selectionAnimOffset)
    -- Use absolute value for outward-only movement, or keep as-is for in/out movement
    local offset = (sineValue + 1) * 0.5 * self.selectionAnimOffset
    
    return math.floor(offset) -- Return integer offset to avoid sub-pixel positioning
end

function DraggableObject:updatePosition(tileX, tileY, sceneWidth, sceneHeight)
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
    
    -- Validate placement (gameStateManager will be passed from GameStateManager)
    self:validatePlacement(sceneWidth, sceneHeight, nil)
end

function DraggableObject:validatePlacement(sceneWidth, sceneHeight, gameStateManager)
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

function DraggableObject:acceptPlacement()
    if not self.isDragging then return false end
    
    if self.previewPlacementValid then
        self.tileX = self.tileX + self.dragOffsetX
        self.tileY = self.tileY + self.dragOffsetY
    end
    
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.isDragging = false
    self.dragDelayTimer = 0
    
    return true
end

function DraggableObject:cancelDragging()
    if not self.isDragging then return false end
    
    self.tileX = self.originalTileX
    self.tileY = self.originalTileY
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.isDragging = false
    self.dragDelayTimer = 0
    
    return true
end

function DraggableObject:cancelSelection()
    if not self.isSelected then return false end
    
    self.isSelected = false
    self.dragDelayTimer = 0
    
    return true
end

function DraggableObject:reset()
    self.isSelected = false
    self.isDragging = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0
    self.dragDelayTimer = 0
    self.previewPlacementValid = true
    self.invalidPlacementReason = nil
end

return DraggableObject

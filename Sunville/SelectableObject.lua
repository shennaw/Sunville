-- SelectableObject.lua
-- Generic class for any object that can be selected in the game but not dragged

local SelectableObject = {}
SelectableObject.__index = SelectableObject

function SelectableObject.new(mapData, tileX, tileY, name)
    local obj = {
        -- Map data
        mapData = mapData,
        tileX = tileX or 0,
        tileY = tileY or 0,
        name = name or "Unknown",
        
        -- Selection state
        isSelected = false,
        selectClickTileX = 0,
        selectClickTileY = 0,
        
        -- Selection corner animation
        selectionAnimTime = 0,
        selectionAnimDuration = 1.5, -- Full cycle duration in seconds
        selectionAnimOffset = 3, -- Maximum pixel offset for corners
        
        -- Collision masks
        waterMask = nil,
        treeMask = nil
    }
    
    setmetatable(obj, SelectableObject)
    return obj
end

function SelectableObject:setCollisionMasks(waterMask, treeMask)
    self.waterMask = waterMask
    self.treeMask = treeMask
end

function SelectableObject:getWidth()
    return self.mapData and self.mapData.width or 0
end

function SelectableObject:getHeight()
    return self.mapData and self.mapData.height or 0
end

function SelectableObject:isPointInside(tileX, tileY)
    local width = self:getWidth()
    local height = self:getHeight()
    return tileX >= self.tileX and tileX < self.tileX + width and 
           tileY >= self.tileY and tileY < self.tileY + height
end

function SelectableObject:select(tileX, tileY)
    self.isSelected = true
    self.selectClickTileX = tileX
    self.selectClickTileY = tileY
    return true
end

function SelectableObject:updateSelection(dt)
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

function SelectableObject:getSelectionCornerOffset()
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

function SelectableObject:cancelSelection()
    if not self.isSelected then return false end
    
    self.isSelected = false
    return true
end

function SelectableObject:reset()
    self.isSelected = false
end

return SelectableObject

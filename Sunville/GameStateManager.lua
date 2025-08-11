-- GameStateManager.lua
-- Manages the overall game state and coordinates between draggable objects and buttons

local GameStateManager = {}
GameStateManager.__index = GameStateManager

-- Button type constants (defined locally to avoid dependency issues)
local BUTTON_TYPE_SELECTION = "selection"
local BUTTON_TYPE_DRAGGING = "dragging"

function GameStateManager.new()
    local manager = {
        draggableObjects = {},
        selectedObject = nil,
        draggingObject = nil,
        buttonManager = nil,
        waterMask = nil,
        treeMask = nil,
        sceneWidth = 0,
        sceneHeight = 0,
        mapScale = 1
    }
    
    setmetatable(manager, GameStateManager)
    return manager
end

function GameStateManager:setButtonManager(buttonManager)
    self.buttonManager = buttonManager
end

function GameStateManager:setCollisionMasks(waterMask, treeMask)
    self.waterMask = waterMask
    self.treeMask = treeMask
end

function GameStateManager:setSceneDimensions(width, height)
    self.sceneWidth = width
    self.sceneHeight = height
end

function GameStateManager:setMapScale(mapScale)
    self.mapScale = mapScale
end

function GameStateManager:addDraggableObject(id, object)
    self.draggableObjects[id] = object
    object:setCollisionMasks(self.waterMask, self.treeMask)
end

function GameStateManager:getDraggableObject(id)
    return self.draggableObjects[id]
end

function GameStateManager:getDraggableObjectAtPosition(tileX, tileY)
    -- Check objects in reverse order (top to bottom) so top objects are selected first
    local objectIds = {}
    for id, _ in pairs(self.draggableObjects) do
        table.insert(objectIds, id)
    end
    
    -- Sort by Y position (objects with higher Y are "on top")
    table.sort(objectIds, function(a, b)
        local objA = self.draggableObjects[a]
        local objB = self.draggableObjects[b]
        return objA.tileY > objB.tileY
    end)
    
    for _, id in ipairs(objectIds) do
        local object = self.draggableObjects[id]
        if object:isPointInside(tileX, tileY) then
            return object, id
        end
    end
    
    return nil, nil
end

function GameStateManager:checkObjectIntersection(object, tileX, tileY)
    -- Check if the given position would cause this object to intersect with any other objects
    local objectWidth = object:getWidth()
    local objectHeight = object:getHeight()
    
    for id, otherObject in pairs(self.draggableObjects) do
        -- Skip the object itself
        if otherObject ~= object then
            -- Check if the two objects would intersect
            local otherX = otherObject:getCurrentTileX()
            local otherY = otherObject:getCurrentTileY()
            local otherWidth = otherObject:getWidth()
            local otherHeight = otherObject:getHeight()
            
            -- Check for intersection using AABB collision detection
            if tileX < otherX + otherWidth and 
               tileX + objectWidth > otherX and
               tileY < otherY + otherHeight and
               tileY + objectHeight > otherY then
                return true, otherObject -- Objects would intersect
            end
        end
    end
    
    return false, nil -- No intersection
end

function GameStateManager:isOriginalPosition(object, tileX, tileY)
    -- Check if the given position is the original position of the object
    return tileX == object.originalTileX and tileY == object.originalTileY
end

function GameStateManager:selectObject(object, tileX, tileY)
    -- Deselect any previously selected object
    if self.selectedObject then
        self.selectedObject:cancelSelection()
    end
    
    -- Select the new object
    if object and object:select(tileX, tileY) then
        self.selectedObject = object
        self:updateButtonStates()
        return true
    end
    
    return false
end

function GameStateManager:startDragging(object)
    if not object or not self.selectedObject or object ~= self.selectedObject then
        return false
    end
    
    if object:startDragging() then
        self.draggingObject = object
        self.selectedObject = nil
        self:updateButtonStates()
        return true
    end
    
    return false
end

function GameStateManager:updateDrag(dt)
    if self.draggingObject then
        self.draggingObject:updateDrag(dt)
    end
    
    -- Update selection animations for all objects
    for _, object in pairs(self.draggableObjects) do
        object:updateSelection(dt)
    end
end

function GameStateManager:updateDragPosition(tileX, tileY)
    if self.draggingObject then
        self.draggingObject:updatePosition(tileX, tileY, self.sceneWidth, self.sceneHeight)
        -- Validate placement with intersection checking
        self.draggingObject:validatePlacement(self.sceneWidth, self.sceneHeight, self)
    end
end

function GameStateManager:acceptDrag()
    if not self.draggingObject then return false end
    
    -- Check if placement is valid before accepting
    if not self.draggingObject.previewPlacementValid then
        print("Cannot place object: " .. (self.draggingObject.invalidPlacementReason or "Invalid placement"))
        return false
    end
    
    if self.draggingObject:acceptPlacement() then
        self.draggingObject = nil
        self:updateButtonStates()
        return true
    end
    
    return false
end

function GameStateManager:cancelDrag()
    if not self.draggingObject then return false end
    
    if self.draggingObject:cancelDragging() then
        self.draggingObject = nil
        self:updateButtonStates()
        return true
    end
    
    return false
end

function GameStateManager:cancelSelection()
    if self.selectedObject then
        if self.selectedObject:cancelSelection() then
            self.selectedObject = nil
            self:updateButtonStates()
            return true
        end
    end
    
    return false
end

function GameStateManager:handleObjectClick(tileX, tileY)
    local object, objectId = self:getDraggableObjectAtPosition(tileX, tileY)
    
    if object then
        -- If we're already dragging ANY object, don't allow selection of other objects
        if self.draggingObject then
            return false
        end
        
        -- If we're already dragging this object, don't select it
        if self.draggingObject == object then
            return false
        end
        
        -- Select the object
        return self:selectObject(object, tileX, tileY)
    else
        -- Clicked on empty space, cancel any selection
        return self:cancelSelection()
    end
end

function GameStateManager:updateButtonStates(mapScale)
    -- Use passed mapScale or fall back to stored mapScale
    local scale = mapScale or self.mapScale
    
    if not self.buttonManager then 
        print("Warning: updateButtonStates called before buttonManager was set")
        return 
    end
    
    -- Check if required images are loaded
    local labelImages = self:getLabelImages()
    local icons = self:getIcons()
    
    if not (labelImages.left and labelImages.middle and labelImages.right and icons.confirm and icons.cancel) then
        print("Warning: updateButtonStates called before all UI images are loaded")
        return
    end
    
    local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
    
    if self.selectedObject then
        -- Show selection buttons
        self.buttonManager:createSelectionButtons(screenW, screenH, labelImages, icons, {
            move = function() self:startDragging(self.selectedObject) end,
            cancel = function() self:cancelSelection() end
        }, scale)
        
        -- Hide dragging buttons
        self.buttonManager:clearButtonsByType(BUTTON_TYPE_DRAGGING)
        
    elseif self.draggingObject then
        -- Show dragging buttons
        self.buttonManager:createDraggingButtons(screenW, screenH, labelImages, icons, {
            accept = function() self:acceptDrag() end,
            cancel = function() self:cancelDrag() end
        }, scale)
        
        -- Hide selection buttons
        self.buttonManager:clearButtonsByType(BUTTON_TYPE_SELECTION)
        
    else
        -- No object selected or dragging, clear all buttons
        self.buttonManager:clearButtons()
    end
end

function GameStateManager:getLabelImages()
    -- This should be implemented by the main game to provide the actual image references
    return {
        left = nil,
        middle = nil,
        right = nil
    }
end

function GameStateManager:getIcons()
    -- This should be implemented by the main game to provide the actual image references
    return {
        confirm = nil,
        cancel = nil
    }
end

function GameStateManager:drawButtons(labelImages, handImage)
    if self.buttonManager then
        self.buttonManager:drawButtons(labelImages, handImage)
    end
end

function GameStateManager:handleButtonClick(x, y)
    if self.buttonManager then
        return self.buttonManager:handleClick(x, y)
    end
    return nil
end

function GameStateManager:reset()
    -- Reset all objects
    for _, object in pairs(self.draggableObjects) do
        object:reset()
    end
    
    self.selectedObject = nil
    self.draggingObject = nil
    
    if self.buttonManager then
        self.buttonManager:clearButtons()
    end
end

function GameStateManager:getSelectedObject()
    return self.selectedObject
end

function GameStateManager:getDraggingObject()
    return self.draggingObject
end

function GameStateManager:isAnyObjectSelected()
    return self.selectedObject ~= nil
end

function GameStateManager:isAnyObjectDragging()
    return self.draggingObject ~= nil
end

return GameStateManager

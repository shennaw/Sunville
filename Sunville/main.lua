-- main_refactored.lua
-- Refactored main game file using the new class-based architecture

-- Load the new classes
local ActionableObject = require("ActionableObject")
local ButtonManager = require("ButtonManager")
local GameStateManager = require("GameStateManager")

local loadSucceeded = false
local sceneMap = nil
local loadErrorMessage = nil

-- Rendering artifacts
local tilesetImage = nil
local tilesetQuads = {}
local tilesetFirstGid = 1
-- Forest tileset (separate atlas)
local forestImage = nil
local forestQuads = {}
local forestTileW, forestTileH = 32, 32
local mapDrawOffsetX, mapDrawOffsetY = 0, 0
local verticalAnchor = "center" -- options: "top", "center", "bottom"
local mapScale = 2 -- will be recalculated to fit screen while keeping integer scale

-- Game state management
local gameStateManager = nil
local buttonManager = nil

-- UI sprites for selection
local cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg = nil, nil, nil, nil
local moveIconImg, cancelIconImg, confirmIconImg = nil, nil, nil

-- Label images
local labelLeftImg, labelMidImg, labelRightImg, handOpenImg = nil, nil, nil, nil

-- Water detection
local waterMask = nil -- 2D boolean array [y][x]
-- Known water tile ids within this tileset (GIDs). Adjust if needed.
local waterGids = {
  [194] = true,
  [195] = true,
}

-- Wood points system
_G.playerWoodPoints = 0
local woodIconMap = nil
local woodIconImage = nil

-- Wood drop animation system
local woodDrops = {} -- Array of {x, y, targetX, targetY, speed, woodGid, quad}

-- Make createWoodDrop globally accessible
_G.createWoodDrop = nil -- Will be set after function is defined

-- Simple NPC composed of base + hair walking sprites
local player = nil -- Renamed from npc to player
local playerTargetX, playerTargetY = nil, nil -- Target position for movement
local playerMoving = false -- Whether player is currently moving to a target
local playerActionTarget = nil -- The object the player is moving to perform action on
local playerActionType = nil -- The type of action to perform when reaching target
local playerActionInProgress = false -- Whether an action is currently being performed
local playerActionTimer = 0 -- Timer for action duration
local playerActionDuration = 2.0 -- How long axe action takes
local playerFacingDirection = 1 -- 1 for right, -1 for left

-- Trees
local treeMap = nil
local treeTilesetFirstGid = 1
local trees = {}
local treeMask = nil -- 2D boolean array [y][x]
local treeSprite = nil

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function round(x)
  return math.floor(x + 0.5)
end

local function checkNPCCollisionWithObjects(npcX, npcY, npcWidth, npcHeight, gameStateManager)
  if not gameStateManager then return false end
  
  -- Convert NPC pixel position to tile coordinates for collision checking
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  
  -- Calculate the tile area the NPC would occupy
  local npcLeft = math.floor(npcX / tileWidth)
  local npcTop = math.floor(npcY / tileHeight)
  local npcRight = math.floor((npcX + npcWidth - 1) / tileWidth)
  local npcBottom = math.floor((npcY + npcHeight - 1) / tileHeight)
  
  -- Check collision with all actionable objects
  for id, object in pairs(gameStateManager.actionableObjects) do
    local objLeft = object.tileX
    local objTop = object.tileY
    local objRight = objLeft + object:getWidth() - 1
    local objBottom = objTop + object:getHeight() - 1
    
    -- Check if NPC area overlaps with object area
    if npcLeft <= objRight and npcRight >= objLeft and 
       npcTop <= objBottom and npcBottom >= objTop then
      return true, object -- Collision detected
    end
  end
  
  return false -- No collision
end

local function checkPlayerCollisionWithObjects(playerX, playerY, playerWidth, playerHeight, gameStateManager)
  if not gameStateManager then return false end
  
  -- Convert player pixel position to tile coordinates for collision checking
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  
  -- Calculate the tile area the player would occupy
  local playerLeft = math.floor(playerX / tileWidth)
  local playerTop = math.floor(playerY / tileHeight)
  local playerRight = math.floor((playerX + playerWidth - 1) / tileWidth)
  local playerBottom = math.floor((playerY + playerHeight - 1) / tileHeight)
  
  -- Check collision with all actionable objects
  for id, object in pairs(gameStateManager.actionableObjects) do
    local objLeft = object.tileX
    local objTop = object.tileY
    local objRight = objLeft + object:getWidth() - 1
    local objBottom = objTop + object:getHeight() - 1
    
    -- Check if player area overlaps with object area
    if playerLeft <= objRight and playerRight >= objLeft and 
       playerTop <= objBottom and playerBottom >= objTop then
      return true, object -- Collision detected
    end
  end
  
  return false -- No collision
end

local function movePlayerToTarget(dt)
  if not playerMoving or not playerTargetX or not playerTargetY then return end
  
  local dx = playerTargetX - player.x
  local dy = playerTargetY - player.y
  local distance = math.sqrt(dx * dx + dy * dy)
  
  if distance < 5 then -- Close enough to target
    -- Snap player to exact target position
    player.x = playerTargetX
    player.y = playerTargetY
    
    playerMoving = false
    playerTargetX = nil
    playerTargetY = nil
    
    -- Start performing the action
    if playerActionTarget and playerActionType then
      -- Set facing direction for axing based on player position relative to tree
      if playerActionType == "axe" then
        local tileWidth = sceneMap.tilewidth or 16
        local playerGridX = math.floor(player.x / tileWidth)
        local treeLeftEdge = playerActionTarget.tileX
        local treeRightEdge = playerActionTarget.tileX + playerActionTarget:getWidth() - 1
        local treeCenterX = playerActionTarget.tileX + math.floor(playerActionTarget:getWidth() / 2)
        
        -- If player is on the left side of tree center, face right
        -- If player is on the right side of tree center, face left
        if playerGridX < treeCenterX then
          playerFacingDirection = 1 -- Face right
        else
          playerFacingDirection = -1 -- Face left
        end
      end
      
      playerActionInProgress = true
      playerActionTimer = 0
      print("Player reached target, starting " .. playerActionType .. " action on " .. playerActionTarget.name)
      print("Final player position: (" .. player.x .. ", " .. player.y .. ")")
    end
    
    return
  end
  
  -- Simple direct movement - phase through obstacles
  local speed = player.speed
  local moveDistance = speed * dt
  
  if distance > 0 then
    local normalizedDx = dx / distance
    local normalizedDy = dy / distance
    
    local moveX = normalizedDx * moveDistance
    local moveY = normalizedDy * moveDistance
    
    -- Update facing direction
    if math.abs(normalizedDx) > 0.1 then
      playerFacingDirection = normalizedDx > 0 and 1 or -1
    end
    
    -- Apply movement with bounds checking only
    local newX = player.x + moveX
    local newY = player.y + moveY
    
    local worldW = sceneMap.width * sceneMap.tilewidth
    local worldH = sceneMap.height * sceneMap.tileheight
    
    player.x = clamp(newX, 0, worldW - player.width)
    player.y = clamp(newY, 0, worldH - player.height)
    
    -- Update walking animation while moving
    player.frameTime = player.frameTime + dt
    while player.frameTime >= player.frameDuration do
      player.frameTime = player.frameTime - player.frameDuration
      player.frame = player.frame % player.frameCount + 1
    end
    
    -- Reset idle animation
    player.idleTime = 0
    player.idleFrame = 1
  end
  
end

local function updatePlayerAction(dt)
  if not playerActionInProgress then return end
  
  playerActionTimer = playerActionTimer + dt
  
  -- Update axe animation frames
  if playerActionType == "axe" and player then
    player.axeFrameTime = player.axeFrameTime + dt
    while player.axeFrameTime >= player.axeFrameDuration do
      player.axeFrameTime = player.axeFrameTime - player.axeFrameDuration
      player.axeFrame = player.axeFrame % player.axeCount + 1
    end
  end
  
  if playerActionTimer >= playerActionDuration then
    -- Single axe swing completed
    if playerActionTarget and playerActionType == "axe" then
      -- Perform one axe hit through the game state manager
      if gameStateManager then
        gameStateManager:performAction(playerActionTarget, playerActionType)
      end
      
      -- Check if tree still exists and has health
      if playerActionTarget and playerActionTarget.currentHealth and playerActionTarget.currentHealth > 0 then
        -- Tree is still alive, continue axing
        playerActionTimer = 0 -- Reset timer for next swing
        player.axeFrame = 1 -- Reset animation
        player.axeFrameTime = 0
        print("Continuing to axe tree...")
      else
        -- Tree is destroyed or action target is gone, stop axing
        playerActionInProgress = false
        playerActionTimer = 0
        playerActionTarget = nil
        playerActionType = nil
        
        -- Reset axe animation
        if player then
          player.axeFrame = 1
          player.axeFrameTime = 0
        end
        print("Axing completed!")
      end
    else
      -- Non-axe actions work as before
      playerActionInProgress = false
      playerActionTimer = 0
      
      if playerActionTarget and playerActionType then
        if gameStateManager then
          gameStateManager:performAction(playerActionTarget, playerActionType)
        end
        
        playerActionTarget = nil
        playerActionType = nil
        
        if player then
          player.axeFrame = 1
          player.axeFrameTime = 0
        end
      end
    end
  end
end

local function findBestTreePosition(object, playerGridX, playerGridY)
  -- Position player at bottom of tree, either leftmost or rightmost grid of the tree
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  local objectWidth = object:getWidth()
  local objectHeight = object:getHeight()
  
  -- Y position is at the bottom row of the tree
  local targetY = object.tileY + objectHeight - 1
  
  -- Determine if player should be on leftmost or rightmost grid of tree
  local leftmostPosition = object.tileX
  local rightmostPosition = object.tileX + objectWidth - 1
  
  -- Calculate distances to leftmost and rightmost positions
  local distanceToLeft = math.abs(leftmostPosition - playerGridX)
  local distanceToRight = math.abs(rightmostPosition - playerGridX)
  
  local targetX
  if distanceToLeft <= distanceToRight then
    targetX = leftmostPosition -- Position at leftmost grid of tree
  else
    targetX = rightmostPosition + 1 -- Position one grid to the right of tree
  end
  
  -- Convert to pixel coordinates
  local pixelX = targetX * tileWidth
  local pixelY = targetY * tileHeight
  
  return targetX, targetY, pixelX, pixelY
end

local function createWoodDrop(treeTileX, treeTileY, treeWidth, treeHeight, woodAmount)
  if not woodIconMap or not tilesetImage or not tilesetQuads then return end
  
  -- Get wood sprite info
  local woodGid = woodIconMap.layers[1].data[1] -- GID from wood.lua
  if not woodGid or woodGid <= 0 then return end
  
  local localId = woodGid - tilesetFirstGid
  local quad = tilesetQuads[localId + 1]
  if not quad then return end
  
  -- Use tree's center position as spawn coordinate
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  local treeCenterWorldX = (treeTileX + treeWidth / 2) * tileWidth
  local treeCenterWorldY = (treeTileY + treeHeight / 2) * tileHeight
  
  -- Transform world coordinates to screen coordinates
  local treeCenterX = (mapDrawOffsetX + treeCenterWorldX) * mapScale
  local treeCenterY = (mapDrawOffsetY + treeCenterWorldY) * mapScale
  
  -- Debug: Print spawn coordinates
  print("DEBUG: Tree world position (" .. treeCenterWorldX .. ", " .. treeCenterWorldY .. ")")
  print("DEBUG: Tree screen position (" .. treeCenterX .. ", " .. treeCenterY .. ")")
  
  -- Calculate target position (wood icon location)
  local iconX = love.graphics.getWidth() - 150 + 12 -- Center of wood icon
  local iconY = 20 + 12
  
  print("DEBUG: Wood icon position (" .. iconX .. ", " .. iconY .. ")")
  
  -- Create multiple wood drops based on amount
  local numDrops = math.min(3, math.max(1, math.floor(woodAmount / 30))) -- 1-3 drops
  
  for i = 1, numDrops do
    -- Use tree center position as spawn coordinate with small random offset
    local offsetX = love.math.random(-20, 20)
    local offsetY = love.math.random(-20, 20)
    local spawnX = treeCenterX + offsetX
    local spawnY = treeCenterY + offsetY
    
    print("DEBUG: Wood drop " .. i .. " spawning at (" .. spawnX .. ", " .. spawnY .. ")")
    
    local drop = {
      x = spawnX,
      y = spawnY,
      targetX = iconX,
      targetY = iconY,
      speed = 200, -- pixels per second
      woodGid = woodGid,
      quad = quad,
      startTime = love.timer.getTime() + (i * 0.2) -- Stagger the drops
    }
    
    table.insert(woodDrops, drop)
  end
end

local function updateWoodDrops(dt)
  for i = #woodDrops, 1, -1 do
    local drop = woodDrops[i]
    
    -- Check if drop should start moving
    if love.timer.getTime() < drop.startTime then
      goto continue
    end
    
    -- Calculate movement direction
    local dx = drop.targetX - drop.x
    local dy = drop.targetY - drop.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance < 5 then
      -- Drop reached the icon, remove it
      table.remove(woodDrops, i)
    else
      -- Move towards target
      local moveDistance = drop.speed * dt
      local normalizedDx = dx / distance
      local normalizedDy = dy / distance
      
      drop.x = drop.x + normalizedDx * moveDistance
      drop.y = drop.y + normalizedDy * moveDistance
    end
    
    ::continue::
  end
end

local function drawWoodDrops()
  if not tilesetImage then return end
  
  for _, drop in ipairs(woodDrops) do
    -- Only draw if drop should be visible
    if love.timer.getTime() >= drop.startTime then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(tilesetImage, drop.quad, drop.x, drop.y, 0, 1.5, 1.5) -- 1.5x scale
      
      -- Debug: Draw bounding box around wood drop
      love.graphics.setColor(1, 0, 0, 1) -- Red color for debug box
      love.graphics.rectangle("line", drop.x, drop.y, 16 * 1.5, 16 * 1.5) -- 16px tile scaled by 1.5
      
      -- Debug: Show coordinates next to the box
      love.graphics.setColor(1, 1, 0, 1) -- Yellow text
      love.graphics.print(string.format("(%.0f,%.0f)", drop.x, drop.y), drop.x + 25, drop.y - 5)
      love.graphics.setColor(1, 1, 1, 1) -- Reset color
    end
  end
end

local function stopPlayerAction()
  if playerActionInProgress then
    playerActionInProgress = false
    playerActionTimer = 0
    playerActionTarget = nil
    playerActionType = nil
    
    -- Reset axe animation
    if player then
      player.axeFrame = 1
      player.axeFrameTime = 0
    end
    
    print("Player action stopped")
    return true
  end
  return false
end

-- Set global reference
_G.createWoodDrop = createWoodDrop

local function startPlayerAction(object, actionType)
  if not object or not actionType then return false end
  
  -- Convert player's current pixel position to grid coordinates
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  local playerGridX = math.floor(player.x / tileWidth)
  local playerGridY = math.floor(player.y / tileHeight)
  
  -- Calculate target grid position
  local targetGridX, targetGridY, targetPixelX, targetPixelY
  
  if object.objectType == "tree" then
    -- For trees, find the best accessible position around the tree
    targetGridX, targetGridY, targetPixelX, targetPixelY = findBestTreePosition(object, playerGridX, playerGridY)
  else
    -- For other objects, use side positioning
    if playerGridX < object.tileX + math.floor(object:getWidth() / 2) then
      targetGridX = object.tileX - 1 -- To the left
    else
      targetGridX = object.tileX + object:getWidth() -- To the right
    end
    targetGridY = object.tileY + math.floor(object:getHeight() / 2) -- Center vertically
    targetPixelX = targetGridX * tileWidth
    targetPixelY = targetGridY * tileHeight
  end
  
  -- Set target position
  playerTargetX = targetPixelX
  playerTargetY = targetPixelY
  
  -- Set action details
  playerActionTarget = object
  playerActionType = actionType
  playerMoving = true
  
  print("Player moving to " .. object.name .. " to perform " .. actionType .. " action")
  print("Player grid position: (" .. playerGridX .. ", " .. playerGridY .. ")")
  print("Target grid position: (" .. targetGridX .. ", " .. targetGridY .. ")")
  print("Target pixel position: (" .. playerTargetX .. ", " .. playerTargetY .. ")")
  
  return true
end

function love.update(dt)
  -- Update game state
  if gameStateManager then
    gameStateManager:updateDrag(dt)
  end
  
  -- Update wood drops animation
  updateWoodDrops(dt)
  
  -- Trees are now handled by gameStateManager, no separate update needed
  
  -- Pause game logic when in grid mode (dragging mode)
  if gameStateManager and gameStateManager:isAnyObjectDragging() then
    return
  end
  
  if player and sceneMap then
    -- Update player movement
    movePlayerToTarget(dt)
    updatePlayerAction(dt)

    -- Only allow random movement when not performing actions
    if not playerActionInProgress and not playerMoving then
      -- Randomly change direction every 1-3 seconds
      player.changeDirCooldown = player.changeDirCooldown - dt
      if player.changeDirCooldown <= 0 then
        player.changeDirCooldown = love.math.random(1, 3)
        local dirs = {
          {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}, {x = 0, y = 0}
        }
        
        -- Filter out directions that would immediately cause collisions
        local validDirs = {}
        for _, dir in ipairs(dirs) do
          local testX = player.x + dir.x * player.speed * 0.1 -- Test 0.1 second ahead
          local testY = player.y + dir.y * player.speed * 0.1
          local worldW = sceneMap.width * sceneMap.tilewidth
          local worldH = sceneMap.height * sceneMap.tileheight
          testX = clamp(testX, 0, worldW - player.width)
          testY = clamp(testY, 0, worldH - player.height)
          
          if not checkPlayerCollisionWithObjects(testX, testY, player.width, player.height, gameStateManager) then
            table.insert(validDirs, dir)
          end
        end
        
        -- If no valid directions, include stop (0,0) as an option
        if #validDirs == 0 then
          validDirs = {{x = 0, y = 0}}
        end
        
        local pick = validDirs[love.math.random(#validDirs)]
        player.dirX, player.dirY = pick.x, pick.y
      end

                                  -- Grid-based movement: move in only one direction at a time
       local speed = player.speed
       local moveX, moveY = 0, 0
       
       -- Determine which direction to move (prioritize the larger difference)
       if math.abs(player.dirX) > math.abs(player.dirY) then
         -- Move horizontally first
         if player.dirX > 0 then
           moveX = speed * dt
         else
           moveX = -speed * dt
         end
       else
         -- Move vertically first
         if player.dirY > 0 then
           moveY = speed * dt
         else
           moveY = -speed * dt
         end
       end
       
       -- Apply movement
       if moveX ~= 0 then
         local newX = player.x + moveX
         -- Keep inside bounds
         local worldW = sceneMap.width * sceneMap.tilewidth
         newX = clamp(newX, 0, worldW - player.width)
         
         -- Check for collision
         if not checkPlayerCollisionWithObjects(newX, player.y, player.width, player.height, gameStateManager) then
           player.x = newX
         else
           -- Can't move horizontally, try vertical
           if player.dirY ~= 0 then
             local testY = player.y + (player.dirY > 0 and speed * dt or -speed * dt)
             local worldH = sceneMap.height * sceneMap.tileheight
             testY = clamp(testY, 0, worldH - player.height)
             if not checkPlayerCollisionWithObjects(player.x, testY, player.width, player.height, gameStateManager) then
               player.y = testY
             else
               -- Can't move in either direction, stop moving and pick a new direction
               player.dirX, player.dirY = 0, 0
               player.changeDirCooldown = 0.1 -- Force direction change soon
             end
           end
         end
       elseif moveY ~= 0 then
         local newY = player.y + moveY
         -- Keep inside bounds
         local worldH = sceneMap.height * sceneMap.tileheight
         newY = clamp(newY, 0, worldH - player.height)
         
         -- Check for collision
         if not checkPlayerCollisionWithObjects(player.x, newY, player.width, player.height, gameStateManager) then
           player.y = newY
         else
           -- Can't move vertically, try horizontal
           if player.dirX ~= 0 then
             local testX = player.x + (player.dirX > 0 and speed * dt or -speed * dt)
             local worldW = sceneMap.width * sceneMap.tilewidth
             testX = clamp(testX, 0, worldW - player.width)
             if not checkPlayerCollisionWithObjects(testX, player.y, player.width, player.height, gameStateManager) then
               player.x = testX
             else
               -- Can't move in either direction, stop moving and pick a new direction
               player.dirX, player.dirY = 0, 0
               player.changeDirCooldown = 0.1 -- Force direction change soon
             end
           end
         end
       end

       local moving = (player.dirX ~= 0 or player.dirY ~= 0)
       if player.dirX > 0 then player.facing = 1 elseif player.dirX < 0 then player.facing = -1 end
       if moving then
         player.frameTime = player.frameTime + dt
         while player.frameTime >= player.frameDuration do
           player.frameTime = player.frameTime - player.frameDuration
           player.frame = player.frame % player.frameCount + 1
         end
         player.idleTime = 0
         player.idleFrame = 1
       else
         player.frame = 1
         player.frameTime = 0
         player.idleTime = player.idleTime + dt
         while player.idleTime >= player.idleDuration do
           player.idleTime = player.idleTime - player.idleDuration
           player.idleFrame = player.idleFrame % player.idleCount + 1
         end
       end
    end
  end
end

local function screenToTile(screenX, screenY)
  if not sceneMap then return 0, 0 end
  local tileWidth = sceneMap.tilewidth
  local tileHeight = sceneMap.tileheight
  -- Convert from screen pixels to world (pre-scale) pixels
  local worldX = screenX / mapScale
  local worldY = screenY / mapScale
  -- Remove map draw offset used during rendering
  worldX = worldX - mapDrawOffsetX
  worldY = worldY - mapDrawOffsetY
  local tileX = math.floor(worldX / tileWidth)
  local tileY = math.floor(worldY / tileHeight)
  return tileX, tileY
end

local function splitString(input, sep)
  local result = {}
  for part in string.gmatch(input, string.format("[^%s]+", sep)) do
    table.insert(result, part)
  end
  return result
end

local function normalizePath(path)
  -- Convert backslashes to forward slashes and collapse .. segments
  path = path:gsub("\\", "/")
  local parts = splitString(path, "/")
  local stack = {}
  for _, p in ipairs(parts) do
    if p == ".." then
      if #stack > 0 then table.remove(stack) end
    elseif p ~= "." and p ~= "" then
      table.insert(stack, p)
    end
  end
  return table.concat(stack, "/")
end

local function joinPath(a, b)
  if not a or a == "" then return b end
  if not b or b == "" then return a end
  return normalizePath(a .. "/" .. b)
end

local function dirname(path)
  path = path:gsub("\\", "/")
  local i = path:match("^.*()/")
  if i then
    return path:sub(1, i - 1)
  else
    return ""
  end
end

local function recalcScale()
  if not sceneMap then return end
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  local worldW = (sceneMap.width or 0) * tileWidth
  local worldH = (sceneMap.height or 0) * tileHeight
  local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
  if worldW == 0 or worldH == 0 then return end

  -- Fullscreen scaling system - fill entire screen
  local scaleW = screenW / worldW
  local scaleH = screenH / worldH
  
  -- Use the larger scale to fill the screen completely (may crop some content)
  -- This eliminates blank spaces and makes the game truly fullscreen
  local baseScale = math.max(scaleW, scaleH)
  
  -- For crisp pixel art, prefer integer scaling when close enough
  local integerScale = round(baseScale)
  local scaleDifference = math.abs(baseScale - integerScale)
  
  if scaleDifference < 0.1 and integerScale >= 1 then
    -- Use integer scale if it's close to the calculated scale
    mapScale = integerScale
  else
    -- Use exact scale for perfect fullscreen fit
    mapScale = baseScale
  end
  
  -- Ensure minimum scale for usability
  mapScale = math.max(mapScale, 0.1)
end

local function recalcMapOffsets()
  if not sceneMap then return end
  local tileWidth = sceneMap.tilewidth or 16
  local tileHeight = sceneMap.tileheight or 16
  local mapPixelW = (sceneMap.width or 0) * tileWidth
  local mapPixelH = (sceneMap.height or 0) * tileHeight

  local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
  local scaledMapW = mapPixelW * mapScale
  local scaledMapH = mapPixelH * mapScale

  -- Center the scaled map content on screen
  -- This handles cases where the map might be larger than screen due to fullscreen scaling
  local desiredX = (screenW - scaledMapW) * 0.5 / mapScale
  local desiredY = (screenH - scaledMapH) * 0.5 / mapScale

  -- For fullscreen scaling, we want to center the content perfectly
  -- No need for complex anchor logic since we're filling the entire screen
  mapDrawOffsetX = desiredX
  mapDrawOffsetY = desiredY
end

function love.mousepressed(x, y, button)
  if button ~= 1 then return end
  
  -- First check if we clicked on a button
  if gameStateManager then
    local clickedButton = gameStateManager:handleButtonClick(x, y)
    if clickedButton then
      -- Handle different button types
      if clickedButton.actionType == "axe" and gameStateManager.selectedObject then
        local selectedObj = gameStateManager.selectedObject
        if selectedObj.objectType == "tree" then
          -- Start player movement to the tree (don't perform axe action yet)
          startPlayerAction(selectedObj, "axe")
          -- Clear the selection since player is now moving
          gameStateManager:cancelSelection()
          return
        end
      elseif clickedButton.actionType == "cancel" then
        -- Cancel any ongoing action
        stopPlayerAction()
        gameStateManager:cancelSelection()
        return
      end
      -- For other actions, let the button handler perform the action normally
      return -- Button handled the click
    end
  end
  
  -- If player is currently axing, stop the action when clicking elsewhere
  if playerActionInProgress then
    stopPlayerAction()
    -- Also clear any selection
    if gameStateManager then
      gameStateManager:cancelSelection()
    end
  end
  
  -- Convert to tile coordinates
  local tileX, tileY = screenToTile(x, y)
  
  -- Handle object selection/dragging (now includes both houses and trees)
  if gameStateManager then
    gameStateManager:handleObjectClick(tileX, tileY)
  end
end

function love.mousemoved(x, y, dx, dy)
  if not gameStateManager or not gameStateManager:isAnyObjectDragging() then return end
  
  -- Only move objects if the left mouse button is currently held down
  if not love.mouse.isDown(1) then return end
  
  local tileX, tileY = screenToTile(x, y)
  gameStateManager:updateDragPosition(tileX, tileY)
end

function love.resize(w, h)
  -- Recalculate offsets when window changes
  recalcScale()
  recalcMapOffsets()
  
  -- Update button states when window resizes (only if button manager is ready)
  if gameStateManager and gameStateManager.buttonManager then
    gameStateManager:setMapScale(mapScale)
    gameStateManager:updateButtonStates()
  end
end

function love.mousereleased(x, y, button)
  if button ~= 1 then return end
  -- With the new button-based system, mouse release should NOT end dragging
  -- Dragging only ends when Accept or Cancel buttons are clicked
  -- Do nothing here - keep dragging state active
end

-- Mobile touch support
function love.touchpressed(id, x, y, dx, dy, pressure)
  -- Treat touch as left mouse button press
  love.mousepressed(x, y, 1)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  -- Treat touch move as mouse move
  love.mousemoved(x, y, dx, dy)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  -- Treat touch release as left mouse button release
  love.mousereleased(x, y, 1)
end

-- Handle device orientation changes (duplicate function removed)

local function tryLoadScene()
  local ok, resultOrError = pcall(function()
    -- Load the Tiled-exported Lua map (vertical/portrait layout)
    return dofile("Lua Tileset/VERTICAL_MAIN_FARM.lua")
  end)

  if ok then
    sceneMap = resultOrError
    loadSucceeded = type(sceneMap) == "table"
    if not loadSucceeded then
      loadErrorMessage = "Scene file did not return a table"
    end
  else
    loadSucceeded = false
    loadErrorMessage = tostring(resultOrError)
  end
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest", 1)
  if love.math and love.math.setRandomSeed then love.math.setRandomSeed(os.time()) end
  
  -- Mobile-friendly window sizing (now that Love2D is fully initialized)
  local function adjustWindowForMobile()
    local baseWidth, baseHeight = 640, 960
    local aspectRatio = baseWidth / baseHeight
    local screenWidth, screenHeight = love.window.getDesktopDimensions()
    
    -- Calculate optimal window size maintaining aspect ratio
    local windowWidth, windowHeight
    if screenWidth / screenHeight > aspectRatio then
      -- Screen is wider than our aspect ratio - fit to height
      windowHeight = math.min(screenHeight * 0.9, 960) -- Max 90% of screen height
      windowWidth = math.floor(windowHeight * aspectRatio)
    else
      -- Screen is taller than our aspect ratio - fit to width
      windowWidth = math.min(screenWidth * 0.9, 640) -- Max 90% of screen width
      windowHeight = math.floor(windowWidth / aspectRatio)
    end
    
    -- Ensure minimum viable size
    windowWidth = math.max(windowWidth, 480)
    windowHeight = math.max(windowHeight, 720)
    
    -- Only resize if significantly different from current size
    local currentWidth, currentHeight = love.graphics.getWidth(), love.graphics.getHeight()
    if math.abs(currentWidth - windowWidth) > 50 or math.abs(currentHeight - windowHeight) > 50 then
      love.window.setMode(windowWidth, windowHeight, {
        resizable = true,
        minwidth = 480,
        minheight = 720,
        highdpi = true,
        usedpiscale = false
      })
    end
  end
  
  -- Apply mobile-friendly window sizing
  adjustWindowForMobile()
  
  -- Initialize game state management
  gameStateManager = GameStateManager.new()
  buttonManager = ButtonManager.new()
  gameStateManager:setButtonManager(buttonManager)
  
  tryLoadScene()

  -- Build tileset for rendering if the map loaded
  if loadSucceeded and sceneMap.tilesets and #sceneMap.tilesets > 0 then
    local ts = sceneMap.tilesets[1]
    tilesetFirstGid = ts.firstgid or 1

    -- Directly use the known tileset image; avoid reading TSX/TMX at runtime
    local imageSource = "Sunnyside_World_Assets/Tileset/spr_tileset_sunnysideworld_16px.png"
    local okImg, imgOrErr = pcall(function()
      return love.graphics.newImage(imageSource)
    end)
    if not okImg then
      loadSucceeded = false
      loadErrorMessage = "Failed to load tileset image: " .. tostring(imgOrErr)
      return
    end
    tilesetImage = imgOrErr

    -- Build quads for each tile in the tileset
    local tileWidth = sceneMap.tilewidth
    local tileHeight = sceneMap.tileheight
    local imageWidth, imageHeight = tilesetImage:getDimensions()
    local columns = math.floor(imageWidth / tileWidth)
    local rows = math.floor(imageHeight / tileHeight)

    tilesetQuads = {}
    for row = 0, rows - 1 do
      for col = 0, columns - 1 do
        local id = row * columns + col -- local tileset id starting at 0
        tilesetQuads[id + 1] = love.graphics.newQuad(
          col * tileWidth,
          row * tileHeight,
          tileWidth,
          tileHeight,
          imageWidth,
          imageHeight
        )
      end
    end
  end

  -- Load the small house map (same tileset/gids)
  local houseMap = nil
  do
    local ok, resultOrError = pcall(function()
      return dofile("Lua Tileset/small-house.lua")
    end)
    if ok and type(resultOrError) == "table" then
      houseMap = resultOrError
    else
      print("Failed to load small house:", tostring(resultOrError))
    end
  end

  -- Load tree map (2x3 tiles using the main tileset)
  do
    local ok, resultOrError = pcall(function()
      return dofile("Lua Tileset/tree.lua")
    end)
    if ok and type(resultOrError) == "table" then
      treeMap = resultOrError
      if treeMap.tilesets and treeMap.tilesets[1] and treeMap.tilesets[1].firstgid then
        treeTilesetFirstGid = treeMap.tilesets[1].firstgid
      else
        treeTilesetFirstGid = 1
      end
    else
      treeMap = nil
      print("Failed to load tree:", tostring(resultOrError))
    end
  end

  -- Load wood icon
  do
    local ok, resultOrError = pcall(function()
      return dofile("Lua Tileset/wood.lua")
    end)
    if ok and type(resultOrError) == "table" then
      woodIconMap = resultOrError
      print("Wood icon loaded successfully")
    else
      print("Failed to load wood icon:", tostring(resultOrError))
    end
  end

  -- Build water mask from explicit Water layer: any non-zero tile is water
  if loadSucceeded and sceneMap and sceneMap.layers then
    local function getLayerByName(name)
      for _, layer in ipairs(sceneMap.layers) do
        if layer.name == name then return layer end
      end
      return nil
    end
    local waterLayer = getLayerByName("Water")
    if waterLayer and waterLayer.type == "tilelayer" and waterLayer.data then
      waterMask = {}
      local w = waterLayer.width or sceneMap.width
      local h = waterLayer.height or sceneMap.height
      for row = 0, h - 1 do
        local rowTable = {}
        for col = 0, w - 1 do
          local idx = row * w + col + 1
          local gid = waterLayer.data[idx] or 0
          rowTable[col + 1] = gid ~= 0
        end
        waterMask[row + 1] = rowTable
      end
    end
  end

  -- Create some tree objects using ActionableObject
  trees = {}
  if treeMap then
    -- Spawn trees at various locations
    local treePositions = {
      {x = 5, y = 8},
      {x = 12, y = 15},
      {x = 20, y = 10},
      {x = 8, y = 20},
      {x = 25, y = 5}
    }
    
    for i, pos in ipairs(treePositions) do
      local tree = ActionableObject.new(treeMap, pos.x, pos.y, "Tree " .. i, "tree")
      gameStateManager:addActionableObject("tree" .. i, tree)
    end
  end
  treeMask = nil

  if loadSucceeded then
    recalcScale()
    recalcMapOffsets()
    
    -- Set scene dimensions for the game state manager
    gameStateManager:setSceneDimensions(sceneMap.width, sceneMap.height)
    gameStateManager:setCollisionMasks(waterMask, treeMask)
    
    print(string.format(
      "Loaded scene: %dx%d tiles, tile size %dx%d, layers=%d",
      sceneMap.width or -1,
      sceneMap.height or -1,
      sceneMap.tilewidth or -1,
      sceneMap.tileheight or -1,
      sceneMap.layers and #sceneMap.layers or 0
    ))
  else
    print("Failed to load scene:", loadErrorMessage)
  end

  -- Initialize NPC after scene is ready
  do
    local basePath = "Sunnyside_World_Assets/Characters/Human/WALKING/base_walk_strip8.png"
    local hairPath = "Sunnyside_World_Assets/Characters/Human/WALKING/bowlhair_walk_strip8.png"
    local toolsPath = "Sunnyside_World_Assets/Characters/Human/WALKING/tools_walk_strip8.png"
    local baseIdlePath = "Sunnyside_World_Assets/Characters/Human/IDLE/base_idle_strip9.png"
    local hairIdlePath = "Sunnyside_World_Assets/Characters/Human/IDLE/bowlhair_idle_strip9.png"
    local toolsIdlePath = "Sunnyside_World_Assets/Characters/Human/IDLE/tools_idle_strip9.png"
    -- Axe animation sprites
    local baseAxePath = "Sunnyside_World_Assets/Characters/Human/AXE/base_axe_strip10.png"
    local hairAxePath = "Sunnyside_World_Assets/Characters/Human/AXE/bowlhair_axe_strip10.png"
    local toolsAxePath = "Sunnyside_World_Assets/Characters/Human/AXE/tools_axe_strip10.png"
    
    local ok1, baseImg = pcall(love.graphics.newImage, basePath)
    local ok2, hairImg = pcall(love.graphics.newImage, hairPath)
    local ok3, toolsImg = pcall(love.graphics.newImage, toolsPath)
    local ok4, baseIdleImg = pcall(love.graphics.newImage, baseIdlePath)
    local ok5, hairIdleImg = pcall(love.graphics.newImage, hairIdlePath)
    local ok6, toolsIdleImg = pcall(love.graphics.newImage, toolsIdlePath)
    local ok7, baseAxeImg = pcall(love.graphics.newImage, baseAxePath)
    local ok8, hairAxeImg = pcall(love.graphics.newImage, hairAxePath)
    local ok9, toolsAxeImg = pcall(love.graphics.newImage, toolsAxePath)
    
    if ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and ok7 and ok8 and ok9 and 
       baseImg and hairImg and toolsImg and baseIdleImg and hairIdleImg and toolsIdleImg and
       baseAxeImg and hairAxeImg and toolsAxeImg then
      baseImg:setFilter("nearest", "nearest")
      hairImg:setFilter("nearest", "nearest")
      toolsImg:setFilter("nearest", "nearest")
      baseIdleImg:setFilter("nearest", "nearest")
      hairIdleImg:setFilter("nearest", "nearest")
      toolsIdleImg:setFilter("nearest", "nearest")
      baseAxeImg:setFilter("nearest", "nearest")
      hairAxeImg:setFilter("nearest", "nearest")
      toolsAxeImg:setFilter("nearest", "nearest")
      
      local frameCount = 8
      local frameW = baseImg:getWidth() / frameCount
      local frameH = baseImg:getHeight()
      local quads = {}
      for i = 0, frameCount - 1 do
        quads[i + 1] = love.graphics.newQuad(i * frameW, 0, frameW, frameH, baseImg:getWidth(), baseImg:getHeight())
      end
      
      -- Idle frames
      local idleCount = 9
      local idleFrameW = baseIdleImg:getWidth() / idleCount
      local idleFrameH = baseIdleImg:getHeight()
      local idleQuads = {}
      for i = 0, idleCount - 1 do
        idleQuads[i + 1] = love.graphics.newQuad(i * idleFrameW, 0, idleFrameW, idleFrameH, baseIdleImg:getWidth(), baseIdleImg:getHeight())
      end
      
      -- Axe frames
      local axeCount = 10
      local axeFrameW = baseAxeImg:getWidth() / axeCount
      local axeFrameH = baseAxeImg:getHeight()
      local axeQuads = {}
      for i = 0, axeCount - 1 do
        axeQuads[i + 1] = love.graphics.newQuad(i * axeFrameW, 0, axeFrameW, axeFrameH, baseAxeImg:getWidth(), baseAxeImg:getHeight())
      end
      
      player = {
        base = baseImg,
        hair = hairImg,
        tools = toolsImg,
        quads = quads,
        frameCount = frameCount,
        frame = 1,
        frameTime = 0,
        frameDuration = 0.12,
        -- Idle
        idleBase = baseIdleImg,
        idleHair = hairIdleImg,
        idleTools = toolsIdleImg,
        idleQuads = idleQuads,
        idleCount = idleCount,
        idleFrame = 1,
        idleTime = 0,
        idleDuration = 0.15,
        -- Axe animation
        axeBase = baseAxeImg,
        axeHair = hairAxeImg,
        axeTools = toolsAxeImg,
        axeQuads = axeQuads,
        axeCount = axeCount,
        axeFrame = 1,
        axeFrameTime = 0,
        axeFrameDuration = 0.2, -- Slower than walking for dramatic effect
        x = 80,
        y = 160,
        speed = 20, -- pixels/sec in world space
        dirX = 0,
        dirY = 0,
        width = frameW,
        height = frameH,
        changeDirCooldown = 0,
        facing = 1 -- 1 right, -1 left
      }
    else
      print("Failed to load player sprites")
    end
  end

  -- Load selection corner and icons
  local uiBase = "Sunnyside_World_Assets/UI/"
  local function loadUI(name)
    local ok, img = pcall(love.graphics.newImage, uiBase .. name)
    if ok then img:setFilter("nearest", "nearest") return img end
    return nil
  end
  cornerTLImg = loadUI("selectbox_tl.png")
  cornerTRImg = loadUI("selectbox_tr.png")
  cornerBLImg = loadUI("selectbox_bl.png")
  cornerBRImg = loadUI("selectbox_br.png")
  moveIconImg = loadUI("confirm.png")
  cancelIconImg = loadUI("cancel.png")
  confirmIconImg = loadUI("confirm.png")
  axeIconImg = loadUI("axe.png")
  labelLeftImg = loadUI("label_left.png")
  labelMidImg = loadUI("label_middle.png")
  labelRightImg = loadUI("label_right.png")
  handOpenImg = loadUI("hand_open_01.png")
  
  -- Debug: Check if images loaded
  print("Label images loaded:")
  print("  labelLeftImg:", labelLeftImg and "OK" or "FAILED")
  print("  labelMidImg:", labelMidImg and "OK" or "FAILED")
  print("  labelRightImg:", labelRightImg and "OK" or "FAILED")
  print("  handOpenImg:", handOpenImg and "OK" or "FAILED")
  print("  axeIconImg:", axeIconImg and "OK" or "FAILED")
  
  -- Create actionable objects (houses)
  if houseMap then
    local house1 = ActionableObject.new(houseMap, 10, 6, "House 1", "house")
    gameStateManager:addActionableObject("house1", house1)
  end
  
  -- Override the getLabelImages and getIcons methods in GameStateManager
  function gameStateManager:getLabelImages()
    return {
      left = labelLeftImg,
      middle = labelMidImg,
      right = labelRightImg
    }
  end
  
  function gameStateManager:getIcons()
    return {
      confirm = confirmIconImg,
      cancel = cancelIconImg,
      axe = axeIconImg
    }
  end
  
  -- Initial button state update
  gameStateManager:setMapScale(mapScale)
  gameStateManager:updateButtonStates()
end

function love.draw()
  love.graphics.clear(0.08, 0.1, 0.12)
  local y = 32
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Sunville - Refactored Scene Load Test", 24, y)
  y = y + 24

  if loadSucceeded then
    -- Draw map
    if tilesetImage and sceneMap.layers then
      love.graphics.setColor(1, 1, 1)
      love.graphics.push()
      love.graphics.scale(mapScale, mapScale)
      local tileWidth = sceneMap.tilewidth
      local tileHeight = sceneMap.tileheight
      -- Grid will be drawn above the base map while dragging; see below
      love.graphics.setColor(1, 1, 1)

      -- Draw a solid background of grass to cover the entire screen area
      do
        local tileWidth = sceneMap.tilewidth
        local tileHeight = sceneMap.tileheight
        local backgroundGid = 131
        local localId = backgroundGid - tilesetFirstGid
        local grassQuad = tilesetQuads[localId + 1]
        if grassQuad then
          local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
          -- Calculate how many tiles we need to cover the entire screen
          local viewW = screenW / mapScale
          local viewH = screenH / mapScale
          local startCol = math.floor(-mapDrawOffsetX / tileWidth) - 1
          local startRow = math.floor(-mapDrawOffsetY / tileHeight) - 1
          local endCol = math.ceil((viewW - mapDrawOffsetX) / tileWidth) + 1
          local endRow = math.ceil((viewH - mapDrawOffsetY) / tileHeight) + 1
          
          for row = startRow, endRow do
            for col = startCol, endCol do
              love.graphics.draw(
                tilesetImage,
                grassQuad,
                mapDrawOffsetX + col * tileWidth,
                mapDrawOffsetY + row * tileHeight
              )
            end
          end
        end
      end

      for _, layer in ipairs(sceneMap.layers) do
        if layer.type == "tilelayer" and layer.visible ~= false and layer.data then
          local mapWidth = layer.width or sceneMap.width
          local mapHeight = layer.height or sceneMap.height
          for row = 0, mapHeight - 1 do
            for col = 0, mapWidth - 1 do
              local idx = row * mapWidth + col + 1
              local gid = layer.data[idx] or 0
              if gid ~= 0 then
                local localId = gid - tilesetFirstGid
                local quad = tilesetQuads[localId + 1]
                if quad then
                  love.graphics.draw(
                    tilesetImage,
                    quad,
                    mapDrawOffsetX + col * tileWidth + (layer.offsetx or 0),
                    mapDrawOffsetY + row * tileHeight + (layer.offsety or 0)
                  )
                end
              end
            end
          end
        end
      end

      -- Trees are now drawn with other actionable objects below

                              -- Draw non-selected actionable objects first (under the overlay)
                        if gameStateManager then
                          for id, object in pairs(gameStateManager.actionableObjects) do
                            -- Only draw objects that are NOT currently being dragged
                            if not object.isDragging then
                              love.drawActionableObject(object, tilesetImage, tilesetQuads, tilesetFirstGid, tileWidth, tileHeight, sceneMap, mapDrawOffsetX, mapDrawOffsetY, cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg)
                            end
                          end
                        end

                        -- While dragging: darken the map and draw a grid overlay above it
                        if gameStateManager and gameStateManager:isAnyObjectDragging() then
                          local mapPixelW = sceneMap.width * tileWidth
                          local mapPixelH = sceneMap.height * tileHeight
                          -- Darken map underlay
                          love.graphics.setColor(0, 0, 0, 0.25)
                          love.graphics.rectangle("fill", mapDrawOffsetX, mapDrawOffsetY, mapPixelW, mapPixelH)
                          love.graphics.setColor(1, 1, 1, 1)
                        end

                        -- Draw only the selected/dragging object above the dark overlay
                        if gameStateManager then
                          for id, object in pairs(gameStateManager.actionableObjects) do
                            -- Only draw objects that ARE currently being dragged
                            if object.isDragging then
                              love.drawActionableObject(object, tilesetImage, tilesetQuads, tilesetFirstGid, tileWidth, tileHeight, sceneMap, mapDrawOffsetX, mapDrawOffsetY, cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg)
                            end
                          end
                        end

      -- Draw player on top of everything else (most front)
      if player then
        local sx = playerFacingDirection
        -- Set anchor point to center of sprite (48, 32)
        local anchorX = 48
        local anchorY = 32
        local drawX = mapDrawOffsetX + player.x - anchorX
        local drawY = mapDrawOffsetY + player.y - anchorY
        
        -- When facing left, we need to adjust the draw position for the flipped sprite
        if sx == -1 then
          drawX = drawX + player.width -- Move draw position to account for sprite flip
        end
        
        love.graphics.setColor(1, 1, 1, 1)
        
        -- Check if player is performing an axe action
        if playerActionInProgress and playerActionType == "axe" then
          -- Draw axe animation
          local axeQ = player.axeQuads[player.axeFrame]
          if axeQ then
            love.graphics.draw(player.axeBase, axeQ, drawX, drawY, 0, sx, 1)
            love.graphics.draw(player.axeHair, axeQ, drawX, drawY, 0, sx, 1)
            love.graphics.draw(player.axeTools, axeQ, drawX, drawY, 0, sx, 1)
          end
        else
          -- Draw normal walking/idle animation
          local moving = (player.dirX ~= 0 or player.dirY ~= 0) or playerMoving
          if moving then
            local q = player.quads[player.frame]
            if q then
              love.graphics.draw(player.base, q, drawX, drawY, 0, sx, 1)
              love.graphics.draw(player.hair, q, drawX, drawY, 0, sx, 1)
              love.graphics.draw(player.tools, q, drawX, drawY, 0, sx, 1)
            end
          else
            local iq = player.idleQuads[player.idleFrame]
            if iq then
              love.graphics.draw(player.idleBase, iq, drawX, drawY, 0, sx, 1)
              love.graphics.draw(player.idleHair, iq, drawX, drawY, 0, sx, 1)
              love.graphics.draw(player.idleTools, iq, drawX, drawY, 0, sx, 1)
            end
          end
        end
      end

      love.graphics.pop()
    end
    
    -- Draw wood drops (in screen space, not scaled)
    drawWoodDrops()

    -- Draw bottom buttons in screen space (outside of transformed context)
    if gameStateManager then
      gameStateManager:drawButtons({
        left = labelLeftImg,
        middle = labelMidImg,
        right = labelRightImg
      }, handOpenImg)
    end

    -- HUD text
    love.graphics.setColor(0.8, 1, 0.8)
    love.graphics.print("Status: OK (refactored)", 24, y)
    y = y + 24
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("Map: %dx%d tiles", sceneMap.width or 0, sceneMap.height or 0), 24, y)
    y = y + 20
    love.graphics.print(string.format("Tile size: %dx%d px", sceneMap.tilewidth or 0, sceneMap.tileheight or 0), 24, y)
    y = y + 20
    local layerCount = (sceneMap.layers and #sceneMap.layers) or 0
    love.graphics.print(string.format("Layers: %d", layerCount), 24, y)
    y = y + 20
    
    -- Show object states
    if gameStateManager then
      local selectedObj = gameStateManager:getSelectedObject()
      local draggingObj = gameStateManager:getDraggingObject()
      
      if selectedObj then
        love.graphics.print(string.format("Selected: %s @ (%d,%d)", selectedObj.name, selectedObj.tileX, selectedObj.tileY), 24, y)
        y = y + 20
      elseif draggingObj then
        love.graphics.print(string.format("Dragging: %s @ (%d,%d)", draggingObj.name, draggingObj:getCurrentTileX(), draggingObj:getCurrentTileY()), 24, y)
        y = y + 20
        if not draggingObj.previewPlacementValid then
          love.graphics.setColor(1, 0.8, 0.6)
          love.graphics.print(draggingObj.invalidPlacementReason or "Invalid placement", 24, y)
          love.graphics.setColor(1, 1, 1)
          y = y + 20
        end
      end
      
      -- Selection status is now handled by the general object display above
    end
    
    -- Show player status
    if player then
      love.graphics.setColor(0.8, 1, 0.8)
      local tileWidth = sceneMap.tilewidth or 16
      local tileHeight = sceneMap.tileheight or 16
      local gridX = math.floor(player.x / tileWidth)
      local gridY = math.floor(player.y / tileHeight)
      love.graphics.print(string.format("Player: Pixel(%d, %d) Grid(%d, %d)", math.floor(player.x), math.floor(player.y), gridX, gridY), 24, y)
      y = y + 20
      
      love.graphics.setColor(0.7, 0.7, 1)
      love.graphics.print(string.format("Map offset: (%.1f, %.1f) Scale: %.2f", mapDrawOffsetX or 0, mapDrawOffsetY or 0, mapScale or 1), 24, y)
      y = y + 20
      
      if playerMoving then
        love.graphics.setColor(1, 1, 0.8)
        love.graphics.print("Moving to target...", 24, y)
        y = y + 20
      elseif playerActionInProgress then
        love.graphics.setColor(1, 0.8, 0.8)
        love.graphics.print(string.format("Performing %s action... (%.1fs)", playerActionType or "unknown", playerActionDuration - playerActionTimer), 24, y)
        y = y + 20
      else
        love.graphics.setColor(0.8, 0.8, 1)
        love.graphics.print("Idle", 24, y)
        y = y + 20
      end
      
      love.graphics.setColor(1, 1, 1)
    end
    
    -- Draw wood points UI
    if woodIconMap and tilesetImage then
      local iconSize = 24
      local iconX = love.graphics.getWidth() - 150
      local iconY = 20
      
      -- Draw wood icon using the same tileset
      local woodGid = woodIconMap.layers[1].data[1] -- GID 754 from wood.lua
      if woodGid and woodGid > 0 then
        local localId = woodGid - tilesetFirstGid
        local quad = tilesetQuads[localId + 1]
        if quad then
          love.graphics.setColor(1, 1, 1)
          love.graphics.draw(tilesetImage, quad, iconX, iconY, 0, iconSize/16, iconSize/16)
        end
      end
      
      -- Draw wood points text
      love.graphics.setColor(1, 1, 0.8)
      love.graphics.print("Wood: " .. (_G.playerWoodPoints or 0), iconX + iconSize + 8, iconY + 4)
      love.graphics.setColor(1, 1, 1)
    end
  else
    love.graphics.setColor(1, 0.7, 0.7)
    love.graphics.print("Status: FAILED (see console)", 24, y)
    y = y + 24
    if loadErrorMessage then
      love.graphics.setColor(1, 0.6, 0.6)
      love.graphics.printf(loadErrorMessage, 24, y, love.graphics.getWidth() - 48)
    end
  end
end

-- Helper function to draw an actionable object
function love.drawActionableObject(object, tilesetImage, tilesetQuads, tilesetFirstGid, tileWidth, tileHeight, sceneMap, mapDrawOffsetX, mapDrawOffsetY, cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg)
  if not object.mapData or not object.mapData.layers then return end
  
  for _, layer in ipairs(object.mapData.layers) do
    if layer.type == "tilelayer" and layer.visible ~= false and layer.data then
      local mapWidth = layer.width or object.mapData.width
      local mapHeight = layer.height or object.mapData.height
      for row = 0, mapHeight - 1 do
        for col = 0, mapWidth - 1 do
          local idx = row * mapWidth + col + 1
          local gid = layer.data[idx] or 0
          if gid ~= 0 then
            local localId = gid - tilesetFirstGid
            local quad = tilesetQuads[localId + 1]
            if quad then
              local placeTileX = object.tileX + col
              local placeTileY = object.tileY + row
              if object.isDragging then
                placeTileX = placeTileX + object.dragOffsetX
                placeTileY = placeTileY + object.dragOffsetY
              end
              -- While dragging, draw semi-transparent; tint red if invalid
              if object.isDragging then
                if not object.previewPlacementValid then
                  love.graphics.setColor(1, 0.6, 0.6, 0.8)
                else
                  love.graphics.setColor(1, 1, 1, 0.8)
                end
              else
                love.graphics.setColor(1, 1, 1, 1)
              end
              love.graphics.draw(
                tilesetImage,
                quad,
                mapDrawOffsetX + placeTileX * tileWidth + (layer.offsetx or 0),
                mapDrawOffsetY + placeTileY * tileHeight + (layer.offsety or 0)
              )
              love.graphics.setColor(1, 1, 1, 1)
            end
          end
        end
      end
    end
  end
  
  -- Draw selection corners if selected
  if object.isSelected then
    local hw = object:getWidth()
    local hh = object:getHeight()
    local px = mapDrawOffsetX + object.tileX * tileWidth
    local py = mapDrawOffsetY + object.tileY * tileHeight
    
    -- Get animated offset for breathing effect
    local animOffset = object:getSelectionCornerOffset()
    
    local function drawCorner(img, dx, dy)
      if img then love.graphics.draw(img, px + dx, py + dy) end
    end
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Apply outward animation to each corner
    drawCorner(cornerTLImg, -2 - animOffset, -2 - animOffset)
    if cornerTRImg then drawCorner(cornerTRImg, hw * tileWidth - cornerTRImg:getWidth() + 2 + animOffset, -2 - animOffset) end
    if cornerBLImg then drawCorner(cornerBLImg, -2 - animOffset, hh * tileHeight - cornerBLImg:getHeight() + 2 + animOffset) end
    if cornerBRImg then drawCorner(cornerBRImg, hw * tileWidth - cornerBRImg:getWidth() + 2 + animOffset, hh * tileHeight - cornerBRImg:getHeight() + 2 + animOffset) end
  end
  
  -- Draw grid overlay and preview when dragging
  if object.isDragging then
    -- Grid overlay
    local mapPixelW = sceneMap.width * tileWidth
    local mapPixelH = sceneMap.height * tileHeight
    love.graphics.setColor(0.5, 0.8, 1.0, 0.15)
    for gx = 0, mapPixelW - 1, tileWidth do
      love.graphics.line(mapDrawOffsetX + gx + 0.5, mapDrawOffsetY, mapDrawOffsetX + gx + 0.5, mapDrawOffsetY + mapPixelH)
    end
    for gy = 0, mapPixelH - 1, tileHeight do
      love.graphics.line(mapDrawOffsetX, mapDrawOffsetY + gy + 0.5, mapDrawOffsetX + mapPixelW, mapDrawOffsetY + gy + 0.5)
    end
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Preview footprint
    local previewTopLeftX = object:getCurrentTileX()
    local previewTopLeftY = object:getCurrentTileY()
    local hW = object:getWidth()
    local hH = object:getHeight()
    
    -- Footprint fill: blue if valid, red if invalid
    if object.previewPlacementValid then
      love.graphics.setColor(0.25, 0.55, 1.0, 0.18)
    else
      love.graphics.setColor(1.0, 0.4, 0.4, 0.18)
    end
    love.graphics.rectangle(
      "fill",
      mapDrawOffsetX + previewTopLeftX * tileWidth,
      mapDrawOffsetY + previewTopLeftY * tileHeight,
      hW * tileWidth,
      hH * tileHeight
    )
    
    -- Footprint outline: blue if valid, red if invalid
    if object.previewPlacementValid then
      love.graphics.setColor(0.25, 0.6, 1.0, 0.7)
    else
      love.graphics.setColor(1.0, 0.45, 0.45, 0.8)
    end
    for r = 0, hH - 1 do
      for c = 0, hW - 1 do
        love.graphics.rectangle(
          "line",
          mapDrawOffsetX + (previewTopLeftX + c) * tileWidth + 0.5,
          mapDrawOffsetY + (previewTopLeftY + r) * tileHeight + 0.5,
          tileWidth,
          tileHeight
        )
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Show invalid placement reason as text
    if not object.previewPlacementValid and object.invalidPlacementReason then
      love.graphics.setColor(1, 0.3, 0.3, 1)
      local text = object.invalidPlacementReason
      local font = love.graphics.getFont()
      local textW = font:getWidth(text)
      local textH = font:getHeight()
      local textX = mapDrawOffsetX + previewTopLeftX * tileWidth + (hW * tileWidth - textW) / 2
      local textY = mapDrawOffsetY + previewTopLeftY * tileHeight - textH - 5
      
      -- Draw text background
      love.graphics.setColor(0, 0, 0, 0.7)
      love.graphics.rectangle("fill", textX - 2, textY - 2, textW + 4, textH + 4)
      love.graphics.setColor(1, 0.3, 0.3, 1)
      love.graphics.print(text, textX, textY)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

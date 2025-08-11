-- main_refactored.lua
-- Refactored main game file using the new class-based architecture

-- Load the new classes
local DraggableObject = require("DraggableObject")
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

-- Simple NPC composed of base + hair walking sprites
local npc = nil

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

function love.update(dt)
  -- Update game state
  if gameStateManager then
    gameStateManager:updateDrag(dt)
  end
  
  -- Pause game logic when in grid mode (dragging mode)
  if gameStateManager and gameStateManager:isAnyObjectDragging() then
    return
  end
  
  if npc and sceneMap then
    -- Randomly change direction every 1-3 seconds
    npc.changeDirCooldown = npc.changeDirCooldown - dt
    if npc.changeDirCooldown <= 0 then
      npc.changeDirCooldown = love.math.random(1, 3)
      local dirs = {
        {x = 1, y = 0}, {x = -1, y = 0}, {x = 0, y = 1}, {x = 0, y = -1}, {x = 0, y = 0}
      }
      local pick = dirs[love.math.random(#dirs)]
      npc.dirX, npc.dirY = pick.x, pick.y
    end

    local dx = npc.dirX * npc.speed * dt
    local dy = npc.dirY * npc.speed * dt
    local newX = npc.x + dx
    local newY = npc.y + dy

    -- Keep inside bounds
    local worldW = sceneMap.width * sceneMap.tilewidth
    local worldH = sceneMap.height * sceneMap.tileheight
    newX = clamp(newX, 0, worldW - npc.width)
    newY = clamp(newY, 0, worldH - npc.height)

    npc.x, npc.y = newX, newY

    local moving = (npc.dirX ~= 0 or npc.dirY ~= 0)
    if npc.dirX > 0 then npc.facing = 1 elseif npc.dirX < 0 then npc.facing = -1 end
    if moving then
      npc.frameTime = npc.frameTime + dt
      while npc.frameTime >= npc.frameDuration do
        npc.frameTime = npc.frameTime - npc.frameDuration
        npc.frame = npc.frame % npc.frameCount + 1
      end
      npc.idleTime = 0
      npc.idleFrame = 1
    else
      npc.frame = 1
      npc.frameTime = 0
      npc.idleTime = npc.idleTime + dt
      while npc.idleTime >= npc.idleDuration do
        npc.idleTime = npc.idleTime - npc.idleDuration
        npc.idleFrame = npc.idleFrame % npc.idleCount + 1
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
      return -- Button handled the click
    end
  end
  
  -- Convert to tile coordinates
  local tileX, tileY = screenToTile(x, y)
  
  -- Handle object selection/dragging
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

  -- Load tree map (2x2 tiles using the forest tileset, but we only need gid data)
  do
    local ok, resultOrError = pcall(function()
      return dofile("Lua Tileset/big-tree.lua")
    end)
    if ok and type(resultOrError) == "table" then
      treeMap = resultOrError
      if treeMap.tilesets and treeMap.tilesets[1] and treeMap.tilesets[1].firstgid then
        treeTilesetFirstGid = treeMap.tilesets[1].firstgid
      else
        treeTilesetFirstGid = 1
      end
      -- Load forest tileset image and build quads (32px tiles)
      local forestImagePath = "Sunnyside_World_Assets/Tileset/spr_tileset_sunnysideworld_forest_32px.png"
      local okForest, forestImgOrErr = pcall(function()
        return love.graphics.newImage(forestImagePath)
      end)
      if okForest then
        forestImage = forestImgOrErr
        forestImage:setFilter("nearest", "nearest")
        local imageWidth, imageHeight = forestImage:getDimensions()
        local columns = math.floor(imageWidth / forestTileW)
        local rows = math.floor(imageHeight / forestTileH)
        forestQuads = {}
        for row = 0, rows - 1 do
          for col = 0, columns - 1 do
            local id = row * columns + col
            forestQuads[id + 1] = love.graphics.newQuad(
              col * forestTileW,
              row * forestTileH,
              forestTileW,
              forestTileH,
              imageWidth,
              imageHeight
            )
          end
        end
      else
        print("Failed to load forest tileset image:", tostring(forestImgOrErr))
      end
    else
      treeMap = nil
      print("Failed to load big tree:", tostring(resultOrError))
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

  -- Trees disabled for now
  trees = {}
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
    local ok1, baseImg = pcall(love.graphics.newImage, basePath)
    local ok2, hairImg = pcall(love.graphics.newImage, hairPath)
    local ok3, toolsImg = pcall(love.graphics.newImage, toolsPath)
    local ok4, baseIdleImg = pcall(love.graphics.newImage, baseIdlePath)
    local ok5, hairIdleImg = pcall(love.graphics.newImage, hairIdlePath)
    local ok6, toolsIdleImg = pcall(love.graphics.newImage, toolsIdlePath)
    if ok1 and ok2 and ok3 and ok4 and ok5 and ok6 and baseImg and hairImg and toolsImg and baseIdleImg and hairIdleImg and toolsIdleImg then
      baseImg:setFilter("nearest", "nearest")
      hairImg:setFilter("nearest", "nearest")
      toolsImg:setFilter("nearest", "nearest")
      baseIdleImg:setFilter("nearest", "nearest")
      hairIdleImg:setFilter("nearest", "nearest")
      toolsIdleImg:setFilter("nearest", "nearest")
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
      npc = {
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
        x = (sceneMap.width * sceneMap.tilewidth) * 0.5,
        y = (sceneMap.height * sceneMap.tileheight) * 0.5,
        speed = 20, -- pixels/sec in world space
        dirX = 0,
        dirY = 0,
        width = frameW,
        height = frameH,
        changeDirCooldown = 0,
        facing = 1 -- 1 right, -1 left
      }
    else
      print("Failed to load NPC sprites")
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
  
  -- Create draggable objects
  if houseMap then
    local house1 = DraggableObject.new(houseMap, 10, 6, "House 1")
    local house2 = DraggableObject.new(houseMap, 15, 8, "House 2")
    gameStateManager:addDraggableObject("house1", house1)
    gameStateManager:addDraggableObject("house2", house2)
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
      cancel = cancelIconImg
    }
  end
  
  -- Initial button state update
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

      -- Draw NPC after the map
      if npc then
        local sx = npc.facing
        local ox = (sx == -1) and npc.width or 0
        local drawX = mapDrawOffsetX + npc.x + ox
        local drawY = mapDrawOffsetY + npc.y
        local moving = (npc.dirX ~= 0 or npc.dirY ~= 0)
        love.graphics.setColor(1, 1, 1, 1)
        if moving then
          local q = npc.quads[npc.frame]
          if q then
            love.graphics.draw(npc.base, q, drawX, drawY, 0, sx, 1)
            love.graphics.draw(npc.hair, q, drawX, drawY, 0, sx, 1)
            love.graphics.draw(npc.tools, q, drawX, drawY, 0, sx, 1)
          end
        else
          local iq = npc.idleQuads[npc.idleFrame]
          if iq then
            love.graphics.draw(npc.idleBase, iq, drawX, drawY, 0, sx, 1)
            love.graphics.draw(npc.idleHair, iq, drawX, drawY, 0, sx, 1)
            love.graphics.draw(npc.idleTools, iq, drawX, drawY, 0, sx, 1)
          end
        end
      end

                              -- Draw non-selected draggable objects first (under the overlay)
                        if gameStateManager then
                          for id, object in pairs(gameStateManager.draggableObjects) do
                            -- Only draw objects that are NOT currently being dragged
                            if not object.isDragging then
                              love.drawDraggableObject(object, tilesetImage, tilesetQuads, tilesetFirstGid, tileWidth, tileHeight, sceneMap, mapDrawOffsetX, mapDrawOffsetY, cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg)
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
                          for id, object in pairs(gameStateManager.draggableObjects) do
                            -- Only draw objects that ARE currently being dragged
                            if object.isDragging then
                              love.drawDraggableObject(object, tilesetImage, tilesetQuads, tilesetFirstGid, tileWidth, tileHeight, sceneMap, mapDrawOffsetX, mapDrawOffsetY, cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg)
                            end
                          end
                        end

      love.graphics.pop()
    end

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

-- Helper function to draw a draggable object
function love.drawDraggableObject(object, tilesetImage, tilesetQuads, tilesetFirstGid, tileWidth, tileHeight, sceneMap, mapDrawOffsetX, mapDrawOffsetY, cornerTLImg, cornerTRImg, cornerBLImg, cornerBRImg)
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
    local function drawCorner(img, dx, dy)
      if img then love.graphics.draw(img, px + dx, py + dy) end
    end
    love.graphics.setColor(1, 1, 1, 1)
    drawCorner(cornerTLImg, -2, -2)
    if cornerTRImg then drawCorner(cornerTRImg, hw * tileWidth - cornerTRImg:getWidth() + 2, -2) end
    if cornerBLImg then drawCorner(cornerBLImg, -2, hh * tileHeight - cornerBLImg:getHeight() + 2) end
    if cornerBRImg then drawCorner(cornerBRImg, hw * tileWidth - cornerBRImg:getWidth() + 2, hh * tileHeight - cornerBRImg:getHeight() + 2) end
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

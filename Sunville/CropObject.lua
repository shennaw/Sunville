-- Sunville/CropObject.lua
local CropObject = {}
CropObject.__index = CropObject

function CropObject.new(type, tileX, tileY)
    local self = setmetatable({
        cropType = type,
        tileX = tileX,
        tileY = tileY,
        growthStage = 0,
        growthTimer = 30, -- 30 seconds per stage
        isWatered = false
    }, CropObject)
    return self
end

function CropObject:update(dt)
    if self.isWatered and self.growthStage < 5 then
        self.growthTimer = self.growthTimer - dt
        if self.growthTimer <= 0 then
            self.growthStage = self.growthStage + 1
            self.growthTimer = 30
            self.isWatered = false -- Need to re-water for next stage
            return true -- Stage advanced
        end
    end
    return false
end

function CropObject:water()
    self.isWatered = true
end

function CropObject:harvest()
    return self.cropType
end

return CropObject

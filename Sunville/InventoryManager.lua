-- Sunville/InventoryManager.lua
local InventoryManager = {}
InventoryManager.__index = InventoryManager

function InventoryManager.new()
    local self = setmetatable({
        seeds = { beetroot = 5, cabbage = 5, carrot = 5, cauliflower = 5, kale = 5 },
        harvested = { beetroot = 0, cabbage = 0, carrot = 0, cauliflower = 0, kale = 0 }
    }, InventoryManager)
    return self
end

function InventoryManager:hasSeed(type) return (self.seeds[type] or 0) > 0 end
function InventoryManager:getItemCount(type) return self.harvested[type] or 0 end
function InventoryManager:addSeed(type, count) self.seeds[type] = (self.seeds[type] or 0) + (count or 1) end
function InventoryManager:removeSeed(type, count)
    count = count or 1
    if (self.seeds[type] or 0) >= count then
        self.seeds[type] = self.seeds[type] - count
        return true
    end
    return false
end
function InventoryManager:addItem(type, count)
    self.harvested[type] = (self.harvested[type] or 0) + (count or 1)
end

return InventoryManager

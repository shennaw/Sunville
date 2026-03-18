function love.load()
    local walk = love.graphics.newImage("Sunnyside_World_Assets/Characters/Human/WALKING/base_walk_strip8.png")
    local dig = love.graphics.newImage("Sunnyside_World_Assets/Characters/Human/DIG/base_dig_strip13.png")
    print("Walk strip width: " .. walk:getWidth() .. " (8 frames -> " .. (walk:getWidth()/8) .. " per frame)")
    print("Dig strip width: " .. dig:getWidth() .. " (13 frames -> " .. (dig:getWidth()/13) .. " per frame)")
    love.event.quit()
end

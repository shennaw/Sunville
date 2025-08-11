function love.conf(t)
  t.identity = "sunville"
  t.console = true
  t.window.title = "Sunville"
  
  -- Mobile-friendly responsive configuration
  -- Start with base size - will be adjusted in love.load()
  t.window.width = 640
  t.window.height = 960
  t.window.resizable = true -- Allow resizing for different orientations
  t.window.minwidth = 480
  t.window.minheight = 720
  t.window.vsync = 1
  
  -- Mobile-specific settings
  t.window.highdpi = true -- Support high-DPI displays
  t.window.usedpiscale = false -- We'll handle scaling manually
end



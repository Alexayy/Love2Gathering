function love.conf(t)
    t.identity = "love2gathering"
    t.version = "11.5"
    t.window.title = "Love: 2 Gathering"
    t.window.icon = "assets/icons/thb.png"
    t.window.width = 1440
    t.window.height = 900
    t.window.minwidth = 1120
    t.window.minheight = 720
    t.window.resizable = true
    t.window.vsync = 1
    t.console = true
    t.modules.audio = true
    t.modules.physics = false
    t.modules.joystick = false
end

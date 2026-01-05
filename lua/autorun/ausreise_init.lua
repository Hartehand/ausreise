AddCSLuaFile()
AddCSLuaFile("ausreise/sh_shared.lua")
AddCSLuaFile("ausreise/sh_config.lua")
AddCSLuaFile("ausreise/client/cl_menu.lua")
AddCSLuaFile("ausreise/client/cl_caseworker.lua")
AddCSLuaFile("ausreise/client/cl_terminal.lua")

include("ausreise/sh_shared.lua")
include("ausreise/sh_config.lua")

if SERVER then
    include("ausreise/server/sv_network.lua")
    include("ausreise/server/sv_mysql.lua")
    include("ausreise/server/sv_core.lua")
    include("ausreise/server/sv_notifications.lua")
else
    include("ausreise/client/cl_menu.lua")
    include("ausreise/client/cl_caseworker.lua")
    include("ausreise/client/cl_terminal.lua")
end

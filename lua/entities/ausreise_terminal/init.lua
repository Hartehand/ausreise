AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_lab/reciever_cart.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if not Ausreise or not Ausreise.Config then return end
    if not activator:Team() then return end
    local allowed = false
    for _, t in ipairs(Ausreise.Config.TerminalAccessTeams or {}) do
        if t and activator:Team() == t then allowed = true break end
    end
    if not allowed then
        activator:ChatPrint("[Ausreise] Kein Zugriff auf das Terminal.")
        return
    end
    net.Start("ausreise_terminal_data")
    net.SendToServer()
end

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

local function canUseTerminal(ply)
    return Ausreise.IsTerminalUser and Ausreise.IsTerminalUser(ply) or false
end

ENT._denyCooldown = ENT._denyCooldown or {}

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if not Ausreise or not Ausreise.Config then return end
    if not activator:Team() then return end

    if not canUseTerminal(activator) then
        self._denyCooldown[activator] = self._denyCooldown[activator] or 0
        if self._denyCooldown[activator] < CurTime() then
            activator:ChatPrint("[Ausreise] Kein Zugriff auf das Terminal.")
            self._denyCooldown[activator] = CurTime() + 2
        end
        return
    end

    if Ausreise.SendTerminalData then
        Ausreise.SendTerminalData(activator, true)
    end
end

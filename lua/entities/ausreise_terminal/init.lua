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
    if not IsValid(ply) or not ply.Team then return false end
    local teamId = ply:Team()
    local teamName = team.GetName(teamId)
    for _, t in ipairs(Ausreise.Config.TerminalAccessTeams or {}) do
        if t == nil then continue end
        if isnumber(t) and teamId == t then return true end
        if isstring(t) and teamName and string.lower(teamName) == string.lower(t) then return true end
    end
    return false
end

local function sendTerminalData(ply)
    if not Ausreise or not Ausreise.DB or not Ausreise.DB.ready then return end
    Ausreise.DB.query("SELECT steamid64, rpname, submitted_at, valid_until, status FROM ausreise_applications WHERE status IN ('approved','denied') ORDER BY decided_at DESC LIMIT 150", nil, function(rows)
        net.Start("ausreise_terminal_data")
        net.WriteTable(rows or {})
        net.Send(ply)
    end)
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

    sendTerminalData(activator)
end

local cfg = Ausreise.Config or {}
local interval = cfg.NotificationInterval or 300
local notifyCooldown = {}

timer.Create("Ausreise_CaseworkerNotify", interval, 0, function()
    if not Ausreise or not Ausreise.DB then return end
    if not Ausreise.DB.ready then return end
    Ausreise.DB.query("SELECT COUNT(*) as c FROM ausreise_applications WHERE status IN ('submitted','in_progress')", nil, function(rows)
        local count = tonumber(rows[1] and rows[1].c) or 0
        if count < 1 then return end
        for _, ply in ipairs(player.GetAll()) do
            if Ausreise.IsCaseworker(ply) then
                local sid = ply:SteamID64()
                notifyCooldown[sid] = notifyCooldown[sid] or 0
                if notifyCooldown[sid] > CurTime() then continue end
                if DarkRP and DarkRP.notify then
                    DarkRP.notify(ply, 0, 5, "Es gibt " .. count .. " Ausreiseanträge zur Bearbeitung.")
                else
                    ply:ChatPrint("[Ausreise] Es gibt " .. count .. " Ausreiseanträge zur Bearbeitung.")
                end
                notifyCooldown[sid] = CurTime() + (interval * 0.5)
            end
        end
    end)
end)

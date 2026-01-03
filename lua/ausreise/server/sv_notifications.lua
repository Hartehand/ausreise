local cfg = Ausreise.Config or {}
local interval = cfg.NotificationInterval or 300

timer.Create("Ausreise_CaseworkerNotify", interval, 0, function()
    if not Ausreise or not Ausreise.DB then return end
    if not Ausreise.DB.ready then return end
    Ausreise.DB.query("SELECT COUNT(*) as c FROM ausreise_applications WHERE status IN ('submitted','in_progress')", nil, function(rows)
        local count = tonumber(rows[1] and rows[1].c) or 0
        if count < 1 then return end
        for _, ply in ipairs(player.GetAll()) do
            if ply:Team() and table.HasValue(cfg.CaseworkerTeams or {}, ply:Team()) then
                if DarkRP and DarkRP.notify then
                    DarkRP.notify(ply, 0, 5, "Es gibt " .. count .. " Ausreiseantr\u00e4ge zur Bearbeitung.")
                else
                    ply:ChatPrint("[Ausreise] Es gibt " .. count .. " Ausreiseantr\u00e4ge zur Bearbeitung.")
                end
            end
        end
    end)
end)

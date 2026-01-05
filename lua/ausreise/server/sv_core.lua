Ausreise = Ausreise or {}
Ausreise.Net = Ausreise.Net or {}
Ausreise.Status = Ausreise.Status or {}

local cfg = Ausreise.Config or {}
local DB = Ausreise.DB or {}

local rateLimit = {}
local rateLimitNet = {}
local cacheBySteam = {}
local pendingCounts = 0
local terminalWatchers = {}

local NET = Ausreise.Net

local function log(msg)
    print("[Ausreise] " .. msg)
end

local function notify(ply, msg, typ, time)
    if not IsValid(ply) then return end
    if DarkRP and DarkRP.notify then
        DarkRP.notify(ply, typ or 0, time or 5, msg)
    else
        ply:ChatPrint(msg)
    end
end

local function nowSQL()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function isDate(str)
    return str and str:match("^%d%d%d%d%-%d%d%-%d%d$")
end

local function sanitizeFields(data)
    local cleaned = {}
    for _, field in ipairs(cfg.Fields or {}) do
        local key = field.key
        local val = data[key]
        if field.required and (val == nil or val == "") then
            return false, "Pflichtfeld fehlt: " .. key
        end
        if val == nil then continue end
        if field.type == "text" or field.type == "multiline" then
            val = tostring(val)
            if field.maxLen and #val > field.maxLen then
                val = string.Left(val, field.maxLen)
            end
        elseif field.type == "number" then
            val = tonumber(val or 0) or 0
            if field.max and val > field.max then val = field.max end
        elseif field.type == "date" then
            val = tostring(val)
            if not isDate(val) then return false, "Ungültiges Datum" end
        elseif field.type == "dropdown" then
            local found = false
            for _, opt in ipairs(field.options or {}) do
                if opt == val then
                    found = true
                    break
                end
            end
            if not found then return false, "Ungültige Auswahl" end
        elseif field.type == "checkbox" then
            val = val and true or false
        end
        cleaned[key] = val
    end
    return true, cleaned
end

local function resubmitAllowed(oldStatus, decidedAt)
    if not cfg.AllowResubmitAfterDays or oldStatus == Ausreise.Status.submitted or oldStatus == Ausreise.Status.in_progress then
        return false
    end
    local days = tonumber(cfg.AllowResubmitAfterDays)
    if not days or days <= 0 then return false end
    if not decidedAt then return false end
    local y, m, d, hh, mm, ss = decidedAt:match("^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)$")
    local decided = os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss)}) or 0
    return os.time() >= decided + (days * 86400)
end

local function loadApplication(steamid, cb)
    if cacheBySteam[steamid] then return cb(cacheBySteam[steamid]) end
    DB.query("SELECT * FROM ausreise_applications WHERE steamid64 = ? ORDER BY id DESC LIMIT 1", {steamid}, function(data)
        local row = data and data[1]
        cacheBySteam[steamid] = row
        cb(row)
    end, function(err)
        log("DB Fehler loadApplication: " .. tostring(err))
        cb(nil)
    end)
end

local function countVotes(appId, cb)
    DB.query("SELECT vote, COUNT(*) as c FROM ausreise_votes WHERE application_id = ? GROUP BY vote", {appId}, function(rows)
        local yes, no = 0, 0
        for _, r in ipairs(rows) do
            local v = tonumber(r.vote) or 0
            if v == 1 then yes = yes + (tonumber(r.c) or 0) else no = no + (tonumber(r.c) or 0) end
        end
        cb(yes, no)
    end, function(err)
        log("DB Fehler countVotes: " .. tostring(err))
        cb(0, 0)
    end)
end

local function updateStatus(appId, status, cb)
    DB.query("UPDATE ausreise_applications SET status = ?, decided_at = ? WHERE id = ?", {status, nowSQL(), appId}, function()
        if cb then cb(true) end
    end, function(err)
        log("DB Fehler updateStatus: " .. tostring(err))
        if cb then cb(false) end
    end)
end

local function sendApplicationToClient(ply, app, opts)
    opts = opts or {}
    net.Start(NET.Data)
    net.WriteBool(app ~= nil)
    net.WriteBool(opts.open ~= false)
    if app then
        net.WriteUInt(app.id, 32)
        net.WriteString(app.status or "")
        net.WriteString(app.submitted_at or "")
        net.WriteString(app.decided_at or "")
        net.WriteString(app.valid_until or "")
        net.WriteString(app.data_json or "{}")
    end
    net.WriteTable(cfg.Fields or {})
    net.Send(ply)
end

local function refreshPendingCount()
    DB.query("SELECT COUNT(*) as c FROM ausreise_applications WHERE status IN ('submitted','in_progress')", nil, function(rows)
        pendingCounts = tonumber(rows[1] and rows[1].c) or 0
    end, function() pendingCounts = 0 end)
end

local function notifyApplicant(app, approved)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID64() == app.steamid64 then
            notify(ply, approved and "Dein Ausreiseantrag wurde genehmigt." or "Dein Ausreiseantrag wurde abgelehnt.", approved and 0 or 1)
            break
        end
    end
end

local function finalize(appId, appData)
    countVotes(appId, function(yes, no)
        local status
        if yes >= 3 then
            status = Ausreise.Status.approved
        elseif no >= 3 then
            status = Ausreise.Status.denied
        end
        if not status then return end
        updateStatus(appId, status, function(success)
            if not success then return end
            cacheBySteam[appData.steamid64] = nil
            DB.query("SELECT * FROM ausreise_applications WHERE id = ?", {appId}, function(rows)
                local app = rows and rows[1]
                if app then notifyApplicant(app, status == Ausreise.Status.approved) end
            end)
            refreshPendingCount()
        end)
    end)
end

local function getVoteKey(ply)
    if cfg.VoteMode == "per_player" then
        return ply:SteamID64()
    end
    return team.GetName(ply:Team()) or tostring(ply:Team())
end

local function existingVote(appId, teamKey, cb)
    DB.query("SELECT id FROM ausreise_votes WHERE application_id = ? AND team_key = ? LIMIT 1", {appId, teamKey}, function(rows)
        cb(rows and rows[1] ~= nil)
    end, function() cb(false) end)
end

local function canSubmit(ply)
    local sid = ply:SteamID64()
    if rateLimit[sid] and rateLimit[sid] > CurTime() then return false end
    rateLimit[sid] = CurTime() + 2
    return true
end

local function canUseNet(ply)
    local sid = ply:SteamID64()
    if rateLimitNet[sid] and rateLimitNet[sid] > CurTime() then return false end
    rateLimitNet[sid] = CurTime() + 0.4
    return true
end

local function sendCaseworkerList(ply, opts)
    DB.query("SELECT id, steamid64, rpname, submitted_at, status, valid_until FROM ausreise_applications WHERE status IN ('submitted','in_progress') ORDER BY submitted_at ASC", nil, function(rows)
        net.Start(NET.CaseworkerList)
        net.WriteBool(not (opts and opts.open == false))
        net.WriteTable(rows or {})
        net.Send(ply)
    end)
end

local function sendCaseworkerDetail(ply, appId)
    DB.query("SELECT * FROM ausreise_applications WHERE id = ?", {appId}, function(rows)
        local app = rows and rows[1]
        if not app then return end
        DB.query("SELECT team_key, vote, voter_steamid64, voted_at FROM ausreise_votes WHERE application_id = ?", {appId}, function(votes)
            net.Start(NET.CaseworkerDetail)
            net.WriteBool(true)
            net.WriteTable(app)
            net.WriteTable(votes or {})
            net.Send(ply)
        end)
    end, function(err)
        log("DB Fehler Detail: " .. tostring(err))
    end)
end

local function sendTerminalData(ply, opts)
    DB.query("SELECT steamid64, rpname, submitted_at, valid_until, status FROM ausreise_applications WHERE status IN ('approved','denied') ORDER BY decided_at DESC LIMIT 150", nil, function(rows)
        net.Start(NET.TerminalData)
        net.WriteBool(not (opts and opts.open == false))
        net.WriteTable(rows or {})
        net.Send(ply)
    end)
end

local function sendPlayerData(ply, open)
    loadApplication(ply:SteamID64(), function(app)
        sendApplicationToClient(ply, app, {open = open})
    end)
end

local function trackTerminalWatcher(ply)
    terminalWatchers[ply] = CurTime() + 150
end

function Ausreise.SendTerminalData(ply, open)
    if not IsValid(ply) then return end
    sendTerminalData(ply, {open = open})
    if open ~= false then
        trackTerminalWatcher(ply)
    end
end

function Ausreise.SendPlayerData(ply, open)
    if not IsValid(ply) then return end
    sendPlayerData(ply, open)
end

function Ausreise.SendCaseworkerList(ply, open)
    if not IsValid(ply) then return end
    sendCaseworkerList(ply, {open = open})
end

local function insertVote(ply, appId, voteVal)
    local teamKey = getVoteKey(ply)
    DB.query("INSERT INTO ausreise_votes (application_id, team_key, vote, voter_steamid64, voted_at) VALUES (?, ?, ?, ?, ?)", {appId, teamKey, voteVal, ply:SteamID64(), nowSQL()}, function()
        DB.query("SELECT status, steamid64 FROM ausreise_applications WHERE id = ?", {appId}, function(rows)
            local app = rows and rows[1]
            if not app then return end
            if app.status == Ausreise.Status.submitted then
                DB.query("UPDATE ausreise_applications SET status = 'in_progress' WHERE id = ?", {appId}, function()
                    cacheBySteam[app.steamid64] = nil
                end)
            else
                cacheBySteam[app.steamid64] = nil
            end
            finalize(appId, app)
        end)
    end, function(err)
        notify(ply, "Vote fehlgeschlagen: " .. tostring(err), 1)
    end)
end

local function openMenu(ply)
    if not canSubmit(ply) then return end
    sendPlayerData(ply, true)
end

local function openCaseworkerUI(ply)
    if not canUseNet(ply) or not Ausreise.IsCaseworker(ply) then return end
    sendCaseworkerList(ply, {open = true})
end

local function openPlayerUI(ply)
    if not canUseNet(ply) then return end
    sendPlayerData(ply, true)
end

local function handleChat(ply)
    if Ausreise.IsCaseworker(ply) then
        openCaseworkerUI(ply)
    else
        openMenu(ply)
    end
end

hook.Add("PlayerSay", "Ausreise_ChatCommand", function(ply, text)
    local msg = string.Trim(string.lower(text or ""))
    if msg == "/ausreise" then
        handleChat(ply)
        return ""
    elseif msg == "/ausreisesachbearbeiter" or msg == "/ausreise_sb" or msg == "/ausreisevote" then
        openCaseworkerUI(ply)
        return ""
    end
end)

if DarkRP and DarkRP.defineChatCommand then
    DarkRP.defineChatCommand("ausreise", function(ply) handleChat(ply) end)
    DarkRP.defineChatCommand("ausreise_sb", function(ply) openCaseworkerUI(ply) end)
end

-- Network receive handlers
net.Receive(NET.Open, function(_, ply)
    if not canUseNet(ply) then return end
    handleChat(ply)
end)

net.Receive(NET.OpenCaseworker, function(_, ply)
    if not canUseNet(ply) then return end
    openCaseworkerUI(ply)
end)

net.Receive(NET.OpenPlayer, function(_, ply)
    if not canUseNet(ply) then return end
    openPlayerUI(ply)
end)

net.Receive(NET.Submit, function(_, ply)
    if not canUseNet(ply) then return end
    local len = net.ReadUInt(17)
    if len > 64000 then return end
    local json = net.ReadData(len)
    local decoded = util.JSONToTable(json or "") or {}
    local ok, fieldsOrErr = sanitizeFields(decoded)
    if not ok then
        notify(ply, fieldsOrErr, 1)
        return
    end
    local sid = ply:SteamID64()
    loadApplication(sid, function(app)
        if app and not resubmitAllowed(app.status, app.decided_at) then
            notify(ply, "Du hast bereits einen Antrag.", 1)
            return
        end
        local rpname = (ply.getDarkRPVar and ply:getDarkRPVar("rpname")) or ply:Nick()
        local dataJson = util.TableToJSON(fieldsOrErr, false, true)
        DB.query("INSERT INTO ausreise_applications (steamid64, rpname, submitted_at, valid_until, status, data_json) VALUES (?, ?, ?, ?, ?, ?)", {
            sid,
            rpname,
            nowSQL(),
            fieldsOrErr.valid_until or "",
            Ausreise.Status.submitted,
            dataJson,
        }, function()
            cacheBySteam[sid] = nil
            refreshPendingCount()
            notify(ply, "Antrag eingereicht.", 0)
            loadApplication(sid, function(app2) sendApplicationToClient(ply, app2, {open = true}) end)
        end, function(err)
            notify(ply, "Datenbankfehler: " .. tostring(err), 1)
        end)
    end)
end)

net.Receive(NET.CaseworkerList, function(_, ply)
    if not canUseNet(ply) or not Ausreise.IsCaseworker(ply) then return end
    sendCaseworkerList(ply, {open = true})
end)

net.Receive(NET.CaseworkerDetail, function(_, ply)
    if not canUseNet(ply) or not Ausreise.IsCaseworker(ply) then return end
    local appId = net.ReadUInt(32)
    sendCaseworkerDetail(ply, appId)
end)

net.Receive(NET.CaseworkerVote, function(_, ply)
    if not canUseNet(ply) or not Ausreise.IsCaseworker(ply) then return end
    local appId = net.ReadUInt(32)
    local voteVal = net.ReadBool() and 1 or 0
    local teamKey = getVoteKey(ply)
    DB.query("SELECT status FROM ausreise_applications WHERE id = ?", {appId}, function(rows)
        local app = rows and rows[1]
        if not app or (app.status ~= Ausreise.Status.submitted and app.status ~= Ausreise.Status.in_progress) then
            notify(ply, "Antrag nicht verfügbar.", 1)
            return
        end
        existingVote(appId, teamKey, function(exists)
            if exists then
                notify(ply, "Dein Team hat bereits abgestimmt.", 1)
                return
            end
            insertVote(ply, appId, voteVal)
            notify(ply, "Stimme gespeichert.", 0)
            sendCaseworkerDetail(ply, appId)
            refreshPendingCount()
        end)
    end, function(err)
        notify(ply, "Datenbankfehler: " .. tostring(err), 1)
    end)
end)

net.Receive(NET.TerminalData, function(_, ply)
    if not canUseNet(ply) or not Ausreise.IsTerminalUser(ply) then return end
    sendTerminalData(ply, {open = true})
    trackTerminalWatcher(ply)
end)

-- Timers
timer.Create("Ausreise_RefreshPending", 300, 0, refreshPendingCount)

timer.Create("Ausreise_PeriodicRefresh", 60, 0, function()
    if not DB.ready then return end
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end
        if Ausreise.IsCaseworker(ply) then
            sendCaseworkerList(ply, {open = false})
        else
            sendPlayerData(ply, false)
        end
        if terminalWatchers[ply] and terminalWatchers[ply] > CurTime() and Ausreise.IsTerminalUser(ply) then
            sendTerminalData(ply, {open = false})
        elseif terminalWatchers[ply] then
            terminalWatchers[ply] = nil
        end
    end
end)

hook.Add("PlayerDisconnected", "Ausreise_CleanupWatcher", function(ply)
    terminalWatchers[ply] = nil
    rateLimit[ply:SteamID64()] = nil
    rateLimitNet[ply:SteamID64()] = nil
end)

-- Init hooks
hook.Add("InitPostEntity", "Ausreise_InitialCount", function()
    timer.Simple(3, refreshPendingCount)
end)

Ausreise.SendApplicationToClient = sendApplicationToClient

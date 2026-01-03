util.AddNetworkString("ausreise_open")
util.AddNetworkString("ausreise_data")
util.AddNetworkString("ausreise_submit")
util.AddNetworkString("ausreise_submit_result")
util.AddNetworkString("ausreise_caseworker_list")
util.AddNetworkString("ausreise_caseworker_vote")
util.AddNetworkString("ausreise_caseworker_detail")
util.AddNetworkString("ausreise_terminal_data")

Ausreise = Ausreise or {}
Ausreise.Status = Ausreise.Status or {
    submitted = "submitted",
    in_progress = "in_progress",
    approved = "approved",
    denied = "denied",
}

local cfg = Ausreise.Config or {}
local DB = Ausreise.DB or {}
local statusNames = cfg.Text and cfg.Text.StatusNames or {}

local rateLimit = {}
local rateLimitNet = {}
local cacheBySteam = {}
local pendingCounts = 0

local function log(msg)
    print("[Ausreise] " .. msg)
end

local function notify(ply, msg, typ, time)
    if DarkRP and DarkRP.notify then
        DarkRP.notify(ply, typ or 0, time or 5, msg)
    else
        ply:ChatPrint(msg)
    end
end

local function isCaseworker(ply)
    local teamIndex = ply:Team()
    for _, t in ipairs(cfg.CaseworkerTeams or {}) do
        if t and teamIndex == t then return true end
    end
    return false
end

local function isTerminalUser(ply)
    local teamIndex = ply:Team()
    for _, t in ipairs(cfg.TerminalAccessTeams or {}) do
        if t and teamIndex == t then return true end
    end
    return false
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
            val = tostring(val):Left(field.maxLen or 1024)
        elseif field.type == "number" then
            val = tonumber(val or 0) or 0
            if field.max and val > field.max then val = field.max end
        elseif field.type == "date" then
            val = tostring(val)
            if not isDate(val) then return false, "Ungültiges Datum" end
        elseif field.type == "dropdown" then
            local found = false
            for _, opt in ipairs(field.options or {}) do
                if opt == val then found = true break end
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

local function refreshPendingCount()
    DB.query("SELECT COUNT(*) as c FROM ausreise_applications WHERE status IN ('submitted','in_progress')", nil, function(rows)
        pendingCounts = tonumber(rows[1] and rows[1].c) or 0
    end, function() pendingCounts = 0 end)
end

local function sendApplicationToClient(ply, app)
    net.Start("ausreise_data")
    net.WriteBool(app ~= nil)
    if app then
        net.WriteUInt(app.id, 32)
        net.WriteString(app.status)
        net.WriteString(app.submitted_at or "")
        net.WriteString(app.decided_at or "")
        net.WriteString(app.valid_until or "")
        net.WriteString(app.data_json or "{}")
    end
    net.WriteTable(cfg.Fields or {})
    net.Send(ply)
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
    rateLimitNet[sid] = CurTime() + 0.5
    return true
end

local function getVoteKey(ply)
    if cfg.VoteMode == "per_player" then
        return ply:SteamID64()
    end
    return team.GetName(ply:Team()) or tostring(ply:Team())
end

local function sendCaseworkerList(ply)
    DB.query("SELECT id, steamid64, rpname, submitted_at, status, valid_until FROM ausreise_applications WHERE status IN ('submitted','in_progress') ORDER BY submitted_at ASC", nil, function(rows)
        local payload = {}
        for _, r in ipairs(rows or {}) do
            table.insert(payload, r)
        end
        net.Start("ausreise_caseworker_list")
        net.WriteTable(payload)
        net.Send(ply)
    end)
end

local function sendCaseworkerDetail(ply, appId)
    DB.query("SELECT * FROM ausreise_applications WHERE id = ?", {appId}, function(rows)
        local app = rows and rows[1]
        if not app then return end
        DB.query("SELECT team_key, vote, voter_steamid64, voted_at FROM ausreise_votes WHERE application_id = ?", {appId}, function(votes)
            net.Start("ausreise_caseworker_detail")
            net.WriteBool(true)
            net.WriteTable(app)
            net.WriteTable(votes or {})
            net.Send(ply)
        end)
    end, function(err)
        log("DB Fehler Detail: " .. tostring(err))
    end)
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

local function insertVote(ply, appId, voteVal)
    local teamKey = getVoteKey(ply)
    DB.query("INSERT INTO ausreise_votes (application_id, team_key, vote, voter_steamid64, voted_at) VALUES (?, ?, ?, ?, ?)", {appId, teamKey, voteVal, ply:SteamID64(), nowSQL()}, function()
        DB.query("SELECT status, steamid64 FROM ausreise_applications WHERE id = ?", {appId}, function(rows)
            local app = rows and rows[1]
            if not app then return end
            if app.status == Ausreise.Status.submitted then
                DB.query("UPDATE ausreise_applications SET status = 'in_progress' WHERE id = ?", {appId})
            end
            finalize(appId, app)
        end)
    end, function(err)
        notify(ply, "Vote fehlgeschlagen: " .. tostring(err), 1)
    end)
end

local function existingVote(appId, teamKey, cb)
    DB.query("SELECT id FROM ausreise_votes WHERE application_id = ? AND team_key = ? LIMIT 1", {appId, teamKey}, function(rows)
        cb(rows and rows[1] ~= nil)
    end, function() cb(false) end)
end

-- Chat command
local function openMenu(ply)
    if not canSubmit(ply) then return end
    loadApplication(ply:SteamID64(), function(app)
        sendApplicationToClient(ply, app)
    end)
end

hook.Add("PlayerSay", "Ausreise_ChatCommand", function(ply, text)
    if text:lower():Trim() == "/ausreise" then
        openMenu(ply)
        return ""
    end
end)

-- Network receive handlers
net.Receive("ausreise_open", function(_, ply)
    if not canUseNet(ply) then return end
    openMenu(ply)
end)

net.Receive("ausreise_submit", function(_, ply)
    if not canUseNet(ply) then return end
    local len = net.ReadUInt(16)
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
        local rpname = ply:getDarkRPVar and ply:getDarkRPVar("rpname") or ply:Nick()
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
            loadApplication(sid, function(app2) sendApplicationToClient(ply, app2) end)
        end, function(err)
            notify(ply, "Datenbankfehler: " .. tostring(err), 1)
        end)
    end)
end)

net.Receive("ausreise_caseworker_list", function(_, ply)
    if not canUseNet(ply) or not isCaseworker(ply) then return end
    sendCaseworkerList(ply)
end)

net.Receive("ausreise_caseworker_detail", function(_, ply)
    if not canUseNet(ply) or not isCaseworker(ply) then return end
    local appId = net.ReadUInt(32)
    sendCaseworkerDetail(ply, appId)
end)

net.Receive("ausreise_caseworker_vote", function(_, ply)
    if not canUseNet(ply) or not isCaseworker(ply) then return end
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

net.Receive("ausreise_terminal_data", function(_, ply)
    if not canUseNet(ply) or not isTerminalUser(ply) then return end
    DB.query("SELECT steamid64, rpname, submitted_at, valid_until, status FROM ausreise_applications WHERE status IN ('approved','denied') ORDER BY decided_at DESC LIMIT 150", nil, function(rows)
        net.Start("ausreise_terminal_data")
        net.WriteTable(rows or {})
        net.Send(ply)
    end)
end)

-- Pending refresh for notifications
timer.Create("Ausreise_RefreshPending", 300, 0, refreshPendingCount)

-- Init hook to ensure early count
hook.Add("InitPostEntity", "Ausreise_InitialCount", function()
    timer.Simple(3, refreshPendingCount)
end)

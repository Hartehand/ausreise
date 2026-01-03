Ausreise = Ausreise or {}
Ausreise.DB = Ausreise.DB or {}

local cfg = Ausreise.Config or {}
local DB = Ausreise.DB

local function log(msg)
    print("[Ausreise][SQL] " .. msg)
end

local function logError(msg)
    MsgC(Color(255, 0, 0), "[Ausreise][SQL ERROR] " .. msg .. "\n")
end

local function ensureMysqloo()
    if DB.adapter ~= "mysqloo" then return end
    if mysqloo then return true end
    logError("mysqloo nicht gefunden, versuche tmysql4.")
    DB.adapter = "tmysql4"
    return false
end

local function ensureTmysql()
    if DB.adapter ~= "tmysql4" then return end
    if TMySQL or tmysql then return true end
    logError("tmysql4 nicht gefunden.")
    return false
end

local function connectMysqloo()
    if not ensureMysqloo() then return end
    local c = cfg.Database
    local db = mysqloo.connect(c.host, c.username, c.password, c.database, c.port)
    function db:onConnected()
        log("Verbindung erfolgreich (mysqloo).")
        DB.obj = self
        DB.ready = true
        if c.autoCreate then
            DB.createTables()
        end
    end
    function db:onConnectionFailed(err)
        logError("Verbindung fehlgeschlagen (mysqloo): " .. tostring(err))
    end
    db:connect()
end

local function connectTmysql()
    if not ensureTmysql() then return end
    local c = cfg.Database
    DB.obj, err = (tmysql or TMySQL).Connect(c.host, c.username, c.password, c.database, c.port, nil, nil, nil, nil)
    if err then
        logError("Verbindung fehlgeschlagen (tmysql4): " .. tostring(err))
        return
    end
    log("Verbindung erfolgreich (tmysql4).")
    DB.ready = true
    if c.autoCreate then
        DB.createTables()
    end
end

function DB.connect()
    DB.adapter = cfg.Database.adapter == "tmysql4" and "tmysql4" or "mysqloo"
    if DB.adapter == "mysqloo" then
        connectMysqloo()
    else
        connectTmysql()
    end
end

local function queryMysqloo(sql, params, callback, errback)
    if not DB.obj or DB.obj:status() ~= mysqloo.DATABASE_CONNECTED then
        return errback and errback("keine Verbindung")
    end
    if params and #params > 0 then
        local stmt = DB.obj:prepare(sql)
        if not stmt then return errback and errback("prepare fehlgeschlagen") end
        for i, v in ipairs(params) do
            stmt:setString(i, tostring(v))
        end
        function stmt:onSuccess(data)
            if callback then callback(data or {}) end
        end
        function stmt:onError(err)
            if errback then errback(err) else logError(err) end
        end
        stmt:start()
    else
        local q = DB.obj:query(sql)
        function q:onSuccess(data)
            if callback then callback(data or {}) end
        end
        function q:onError(err)
            if errback then errback(err) else logError(err) end
        end
        q:start()
    end
end

local function queryTmysql(sql, params, callback, errback)
    if not DB.obj then return errback and errback("keine Verbindung") end
    DB.obj:Query(sql, params, function(result)
        if not result or result[1].error then
            if errback then errback(result and result[1].error) end
            return
        end
        if callback then callback(result[1].data or {}) end
    end)
end

function DB.query(sql, params, callback, errback)
    if DB.adapter == "tmysql4" then
        return queryTmysql(sql, params, callback, errback)
    else
        return queryMysqloo(sql, params, callback, errback)
    end
end

function DB.escape(str)
    if DB.adapter == "tmysql4" and DB.obj and DB.obj.Escape then
        return DB.obj:Escape(str)
    end
    if DB.adapter == "mysqloo" and mysqloo then
        return mysqloo.Escape(str)
    end
    return str
end

local function createTablesSql()
    local apps = [[
        CREATE TABLE IF NOT EXISTS ausreise_applications (
            id INT AUTO_INCREMENT PRIMARY KEY,
            steamid64 VARCHAR(32) NOT NULL,
            rpname VARCHAR(255) NOT NULL,
            submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            valid_until DATE NULL,
            status VARCHAR(32) NOT NULL,
            data_json TEXT NOT NULL,
            decided_at DATETIME NULL
        ) CHARACTER SET utf8mb4;
    ]]

    local votes = [[
        CREATE TABLE IF NOT EXISTS ausreise_votes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            application_id INT NOT NULL,
            team_key VARCHAR(64) NOT NULL,
            vote TINYINT NOT NULL,
            voter_steamid64 VARCHAR(32) NOT NULL,
            voted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_vote (application_id, team_key),
            FOREIGN KEY (application_id) REFERENCES ausreise_applications(id) ON DELETE CASCADE
        ) CHARACTER SET utf8mb4;
    ]]

    return {apps, votes}
end

function DB.createTables()
    local stmts = createTablesSql()
    for _, sql in ipairs(stmts) do
        DB.query(sql, nil, function()
            log("Tabelle geprüft/erstellt.")
        end, function(err)
            logError("CreateTable fehlgeschlagen: " .. tostring(err))
        end)
    end
end

hook.Add("Initialize", "Ausreise_DBConnect", function()
    timer.Simple(1, DB.connect)
end)

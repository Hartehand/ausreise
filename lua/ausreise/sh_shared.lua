Ausreise = Ausreise or {}
Ausreise.Config = Ausreise.Config or {}

local cfg = Ausreise.Config

Ausreise.Status = {
    submitted = "submitted",
    in_progress = "in_progress",
    approved = "approved",
    denied = "denied",
}

Ausreise.Net = {
    Open = "ausreise_open",
    OpenCaseworker = "ausreise_open_caseworker",
    OpenPlayer = "ausreise_open_player",
    Data = "ausreise_data",
    Submit = "ausreise_submit",
    SubmitResult = "ausreise_submit_result",
    CaseworkerList = "ausreise_caseworker_list",
    CaseworkerVote = "ausreise_caseworker_vote",
    CaseworkerDetail = "ausreise_caseworker_detail",
    TerminalData = "ausreise_terminal_data",
}

local function buildTeamLookup(list)
    local ids = {}
    local names = {}
    for _, v in ipairs(list or {}) do
        if v == nil then continue end
        if isnumber(v) then
            ids[v] = true
        elseif isstring(v) then
            names[string.lower(v)] = true
        end
    end
    return {ids = ids, names = names}
end

local function teamInLookup(teamId, lookup)
    if lookup.ids[teamId] then return true end
    local tName = team.GetName(teamId)
    if not tName then return false end
    return lookup.names[string.lower(tName)] == true
end

function Ausreise.RefreshLookups()
    Ausreise.Lookup = Ausreise.Lookup or {}
    Ausreise.Lookup.caseworker = buildTeamLookup(cfg.CaseworkerTeams)
    Ausreise.Lookup.terminal = buildTeamLookup(cfg.TerminalAccessTeams)
end

function Ausreise.IsCaseworker(ply)
    if not IsValid(ply) or not ply.Team then return false end
    return teamInLookup(ply:Team(), Ausreise.Lookup.caseworker or {ids = {}, names = {}})
end

function Ausreise.IsTerminalUser(ply)
    if not IsValid(ply) or not ply.Team then return false end
    return teamInLookup(ply:Team(), Ausreise.Lookup.terminal or {ids = {}, names = {}})
end

function Ausreise.EnsureConfigTexts()
    cfg.Text = cfg.Text or {}
    cfg.Text.StatusNames = cfg.Text.StatusNames or {
        submitted = "Antrag gestellt",
        in_progress = "In Bearbeitung",
        approved = "Ausreise genehmigt",
        denied = "Ausreise abgelehnt",
    }
end

Ausreise.RefreshLookups()
Ausreise.EnsureConfigTexts()

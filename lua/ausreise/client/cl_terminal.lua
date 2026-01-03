local NET = Ausreise.Net

local termState = {
    frame = nil,
    rows = {},
}

local function buildList(frame, rows)
    local search = vgui.Create("DTextEntry", frame)
    search:Dock(TOP)
    search:SetTall(24)
    search:SetPlaceholderText("Suche nach SteamID64 oder Name...")

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:AddColumn("Name")
    list:AddColumn("SteamID64")
    list:AddColumn("Gestellt am")
    list:AddColumn("Gültig bis")
    list:AddColumn("Status")

    local function populate(filter)
        list:Clear()
        local term = filter and string.lower(filter) or ""
        for _, r in ipairs(rows or {}) do
            local match = term == "" or (r.steamid64 and string.find(r.steamid64, term, 1, true)) or (r.rpname and string.find(string.lower(r.rpname), term, 1, true))
            if match then
                list:AddLine(r.rpname, r.steamid64, r.submitted_at, r.valid_until, r.status)
            end
        end
    end

    populate()
    search.OnChange = function(self) populate(self:GetValue() or "") end
end

local function openTerminal(rows, forceOpen)
    termState.rows = rows or {}
    if not forceOpen and not IsValid(termState.frame) then return end
    if IsValid(termState.frame) then termState.frame:Remove() end

    local frame = vgui.Create("DFrame")
    frame:SetSize(740, 540)
    frame:Center()
    frame:SetTitle("Ausreise-Terminal")
    frame:MakePopup()
    termState.frame = frame

    buildList(frame, termState.rows)
end

net.Receive(NET.TerminalData, function()
    local shouldOpen = net.ReadBool()
    local rows = net.ReadTable() or {}
    openTerminal(rows, shouldOpen)
end)

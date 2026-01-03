local function openList(rows)
    local frame = vgui.Create("DFrame")
    frame:SetSize(700, 520)
    frame:Center()
    frame:SetTitle("Ausreiseantr\u00e4ge - Sachbearbeiter")
    frame:MakePopup()

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:AddColumn("ID")
    list:AddColumn("Name")
    list:AddColumn("SteamID64")
    list:AddColumn("Status")
    list:AddColumn("Eingang")
    list:AddColumn("G\u00fcltig bis")

    for _, r in ipairs(rows or {}) do
        list:AddLine(r.id, r.rpname, r.steamid64, r.status, r.submitted_at, r.valid_until)
    end

    list.OnRowSelected = function(_, _, line)
        net.Start("ausreise_caseworker_detail")
        net.WriteUInt(tonumber(line:GetColumnText(1)) or 0, 32)
        net.SendToServer()
    end
end

local function openDetail(app, votes)
    local frame = vgui.Create("DFrame")
    frame:SetSize(600, 560)
    frame:Center()
    frame:SetTitle("Antrag #" .. app.id)
    frame:MakePopup()

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)

    local data = util.JSONToTable(app.data_json or "{}") or {}

    local lbl = vgui.Create("DLabel", scroll)
    lbl:Dock(TOP)
    lbl:SetText("Status: " .. (app.status or "?"))
    lbl:SetTall(24)

    for k, v in pairs(data) do
        local pnl = vgui.Create("DPanel", scroll)
        pnl:Dock(TOP)
        pnl:SetTall(40)
        pnl:SetPaintBackground(false)
        local l1 = vgui.Create("DLabel", pnl)
        l1:SetPos(0, 0)
        l1:SetText(k .. ":")
        l1:SizeToContents()
        local l2 = vgui.Create("DLabel", pnl)
        l2:SetPos(0, 18)
        l2:SetText(tostring(v))
        l2:SizeToContents()
    end

    local votesPanel = vgui.Create("DPanel", scroll)
    votesPanel:Dock(TOP)
    votesPanel:SetTall(120)
    votesPanel:SetPaintBackground(false)

    local lVotes = vgui.Create("DLabel", votesPanel)
    lVotes:SetPos(0, 0)
    lVotes:SetText("Stimmen:")
    lVotes:SizeToContents()

    local y = 18
    for _, v in ipairs(votes or {}) do
        local line = vgui.Create("DLabel", votesPanel)
        line:SetPos(0, y)
        line:SetText(string.format("%s - %s (%s)", v.team_key, (tonumber(v.vote) == 1) and "JA" or "NEIN", v.voter_steamid64))
        line:SizeToContents()
        y = y + 16
    end

    local btnApprove = vgui.Create("DButton", frame)
    btnApprove:Dock(BOTTOM)
    btnApprove:SetTall(28)
    btnApprove:SetText("Zustimmen")
    btnApprove.DoClick = function()
        net.Start("ausreise_caseworker_vote")
        net.WriteUInt(app.id, 32)
        net.WriteBool(true)
        net.SendToServer()
        frame:Close()
    end

    local btnDeny = vgui.Create("DButton", frame)
    btnDeny:Dock(BOTTOM)
    btnDeny:SetTall(28)
    btnDeny:SetText("Ablehnen")
    btnDeny.DoClick = function()
        net.Start("ausreise_caseworker_vote")
        net.WriteUInt(app.id, 32)
        net.WriteBool(false)
        net.SendToServer()
        frame:Close()
    end
end

net.Receive("ausreise_caseworker_list", function()
    local rows = net.ReadTable() or {}
    openList(rows)
end)

net.Receive("ausreise_caseworker_detail", function()
    local ok = net.ReadBool()
    if not ok then return end
    local app = net.ReadTable()
    local votes = net.ReadTable()
    openDetail(app, votes)
end)

concommand.Add("ausreise_caseworker", function()
    net.Start("ausreise_caseworker_list")
    net.SendToServer()
end)

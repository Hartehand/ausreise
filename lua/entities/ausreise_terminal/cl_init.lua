include("shared.lua")

local function openTerminal(rows)
    local frame = vgui.Create("DFrame")
    frame:SetSize(720, 520)
    frame:Center()
    frame:SetTitle("Ausreise-Terminal")
    frame:MakePopup()

    local search = vgui.Create("DTextEntry", frame)
    search:Dock(TOP)
    search:SetTall(24)
    search:SetPlaceholderText("Suche nach SteamID64 oder Name...")

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:AddColumn("Name")
    list:AddColumn("SteamID64")
    list:AddColumn("Gestellt am")
    list:AddColumn("G\u00fcltig bis")
    list:AddColumn("Status")

    local function populate(filter)
        list:Clear()
        for _, r in ipairs(rows or {}) do
            local term = filter and filter:lower() or ""
            local match = term == "" or (r.steamid64 and string.find(r.steamid64, term, 1, true)) or (r.rpname and string.find(string.lower(r.rpname), term, 1, true))
            if match then
                list:AddLine(r.rpname, r.steamid64, r.submitted_at, r.valid_until, r.status)
            end
        end
    end

    populate()

    search.OnChange = function(self)
        populate(self:GetValue() or "")
    end
end

net.Receive("ausreise_terminal_data", function()
    local rows = net.ReadTable() or {}
    openTerminal(rows)
end)

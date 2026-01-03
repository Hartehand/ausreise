local cfg = Ausreise.Config or {}

local function openForm(existing)
    local frame = vgui.Create("DFrame")
    frame:SetSize(520, 600)
    frame:Center()
    frame:SetTitle("Ausreiseantrag")
    frame:MakePopup()

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)

    local inputs = {}
    for _, field in ipairs(cfg.Fields or {}) do
        local pnl = vgui.Create("DPanel", scroll)
        pnl:Dock(TOP)
        pnl:DockMargin(0, 0, 0, 8)
        pnl:SetTall(field.type == "multiline" and 140 or 70)
        pnl:SetPaintBackground(false)

        local lbl = vgui.Create("DLabel", pnl)
        lbl:SetPos(0, 0)
        lbl:SetText(field.label .. (field.required and " *" or ""))
        lbl:SizeToContents()

        local helper = vgui.Create("DLabel", pnl)
        helper:SetPos(0, 18)
        helper:SetText(field.helper or "")
        helper:SetTextColor(Color(160, 160, 160))
        helper:SizeToContents()

        local input
        if field.type == "text" then
            input = vgui.Create("DTextEntry", pnl)
            input:SetPos(0, 36)
            input:SetSize(480, 24)
            if existing then input:SetText(existing[field.key] or "") end
        elseif field.type == "number" then
            input = vgui.Create("DTextEntry", pnl)
            input:SetPos(0, 36)
            input:SetSize(200, 24)
            input:SetNumeric(true)
            if existing then input:SetText(tostring(existing[field.key] or "")) end
        elseif field.type == "date" then
            input = vgui.Create("DTextEntry", pnl)
            input:SetPos(0, 36)
            input:SetSize(200, 24)
            input:SetPlaceholderText("YYYY-MM-DD")
            if existing then input:SetText(existing[field.key] or "") end
        elseif field.type == "multiline" then
            input = vgui.Create("DTextEntry", pnl)
            input:SetPos(0, 36)
            input:SetSize(480, 90)
            input:SetMultiline(true)
            if existing then input:SetText(existing[field.key] or "") end
        elseif field.type == "dropdown" then
            input = vgui.Create("DComboBox", pnl)
            input:SetPos(0, 36)
            input:SetSize(260, 24)
            for _, opt in ipairs(field.options or {}) do input:AddChoice(opt) end
            if existing and existing[field.key] then input:SetValue(existing[field.key]) end
        elseif field.type == "checkbox" then
            input = vgui.Create("DCheckBoxLabel", pnl)
            input:SetPos(0, 36)
            input:SetText("Ja")
            if existing then input:SetChecked(existing[field.key] == true) end
        end
        inputs[field.key] = input
    end

    local submit = vgui.Create("DButton", frame)
    submit:Dock(BOTTOM)
    submit:SetTall(32)
    submit:SetText("Antrag absenden")
    submit.DoClick = function()
        local payload = {}
        for _, field in ipairs(cfg.Fields or {}) do
            local input = inputs[field.key]
            if not IsValid(input) then continue end
            if field.type == "checkbox" then
                payload[field.key] = input:GetChecked()
            elseif field.type == "dropdown" then
                local chosen
                if input.GetSelectedID and input.GetOptionText then
                    local id = input:GetSelectedID()
                    if id and id > 0 then
                        chosen = input:GetOptionText(id)
                    end
                end
                if not chosen or chosen == "" then
                    chosen = input:GetValue()
                end
                payload[field.key] = chosen
            else
                payload[field.key] = input:GetValue()
            end
        end
        local json = util.TableToJSON(payload, false, true) or ""
        net.Start("ausreise_submit")
        net.WriteUInt(#json, 16)
        net.WriteData(json, #json)
        net.SendToServer()
        frame:Close()
    end
end

local function openStatus(app)
    local data = util.JSONToTable(app.data_json or "{}") or {}
    local frame = vgui.Create("DFrame")
    frame:SetSize(520, 600)
    frame:Center()
    frame:SetTitle("Ausreiseantrag - Status")
    frame:MakePopup()

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)

    local lbl = vgui.Create("DLabel", scroll)
    lbl:Dock(TOP)
    lbl:SetWrap(true)
    lbl:SetTall(40)
    lbl:SetText("Status: " .. (cfg.Text.StatusNames[app.status] or app.status))

    for _, field in ipairs(cfg.Fields or {}) do
        local val = data[field.key]
        local pnl = vgui.Create("DPanel", scroll)
        pnl:Dock(TOP)
        pnl:DockMargin(0, 0, 0, 6)
        pnl:SetTall(50)
        pnl:SetPaintBackground(false)

        local lbl2 = vgui.Create("DLabel", pnl)
        lbl2:SetPos(0, 0)
        lbl2:SetText(field.label)
        lbl2:SizeToContents()

        local lbl3 = vgui.Create("DLabel", pnl)
        lbl3:SetPos(0, 18)
        lbl3:SetText(tostring(val or "-"))
        lbl3:SizeToContents()
    end

    if app.decided_at and app.decided_at ~= "" then
        local info = vgui.Create("DLabel", scroll)
        info:Dock(TOP)
        info:SetWrap(true)
        info:SetTall(24)
        info:SetText("Entschieden am: " .. (app.decided_at or "-") .. " | Gültig bis: " .. (app.valid_until or "-"))
    end
end

net.Receive("ausreise_data", function()
    local has = net.ReadBool()
    if has then
        local app = {
            id = net.ReadUInt(32),
            status = net.ReadString(),
            submitted_at = net.ReadString(),
            decided_at = net.ReadString(),
            valid_until = net.ReadString(),
            data_json = net.ReadString(),
        }
        cfg.Fields = net.ReadTable() or {}
        openStatus(app)
    else
        cfg.Fields = net.ReadTable() or {}
        openForm()
    end
end)

concommand.Add("ausreise_open", function()
    net.Start("ausreise_open")
    net.SendToServer()
end)

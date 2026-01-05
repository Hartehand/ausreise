local cfg = Ausreise.Config or {}
local NET = Ausreise.Net

local state = {
    lastFields = cfg.Fields or {},
    lastApp = nil,
    statusFrame = nil,
    formFrame = nil,
}

local function ensureFields(fields)
    state.lastFields = fields or cfg.Fields or {}
end

local function closeFrames()
    if IsValid(state.statusFrame) then state.statusFrame:Close() end
    if IsValid(state.formFrame) then state.formFrame:Close() end
end

local function buildInput(field, parent, existing)
    local input
    if field.type == "text" or field.type == "number" or field.type == "date" then
        input = vgui.Create("DTextEntry", parent)
        input:SetPos(0, 36)
        input:SetSize(480, 24)
        if field.type == "number" then input:SetNumeric(true) end
        if field.type == "date" then input:SetPlaceholderText("YYYY-MM-DD") end
        if existing then input:SetText(tostring(existing[field.key] or "")) end
    elseif field.type == "multiline" then
        input = vgui.Create("DTextEntry", parent)
        input:SetPos(0, 36)
        input:SetSize(480, 90)
        input:SetMultiline(true)
        if existing then input:SetText(tostring(existing[field.key] or "")) end
    elseif field.type == "dropdown" then
        input = vgui.Create("DComboBox", parent)
        input:SetPos(0, 36)
        input:SetSize(260, 24)
        for _, opt in ipairs(field.options or {}) do input:AddChoice(opt) end
        if existing and existing[field.key] then input:SetValue(existing[field.key]) end
    elseif field.type == "checkbox" then
        input = vgui.Create("DCheckBoxLabel", parent)
        input:SetPos(0, 36)
        input:SetText("Ja")
        if existing then input:SetChecked(existing[field.key] == true) end
    end
    return input
end

local function openForm(existing)
    if IsValid(state.formFrame) then state.formFrame:Close() end
    local frame = vgui.Create("DFrame")
    frame:SetSize(520, 620)
    frame:Center()
    frame:SetTitle("Ausreiseantrag")
    frame:MakePopup()
    state.formFrame = frame

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)

    local inputs = {}
    for _, field in ipairs(state.lastFields or {}) do
        local pnl = vgui.Create("DPanel", scroll)
        pnl:Dock(TOP)
        pnl:DockMargin(0, 0, 0, 8)
        pnl:SetTall(field.type == "multiline" and 140 or 70)
        pnl:SetPaintBackground(false)

        local lbl = vgui.Create("DLabel", pnl)
        lbl:SetPos(0, 0)
        lbl:SetText((field.label or field.key) .. (field.required and " *" or ""))
        lbl:SizeToContents()

        local helper = vgui.Create("DLabel", pnl)
        helper:SetPos(0, 18)
        helper:SetText(field.helper or "")
        helper:SetTextColor(Color(160, 160, 160))
        helper:SizeToContents()

        local input = buildInput(field, pnl, existing)
        inputs[field.key] = input
    end

    local submit = vgui.Create("DButton", frame)
    submit:Dock(BOTTOM)
    submit:SetTall(32)
    submit:SetText("Antrag absenden")
    submit.DoClick = function()
        local payload = {}
        for _, field in ipairs(state.lastFields or {}) do
            local input = inputs[field.key]
            if not IsValid(input) then continue end
            if field.type == "checkbox" and input.GetChecked then
                payload[field.key] = input:GetChecked()
            elseif field.type == "dropdown" then
                local chosen
                if input.GetSelectedID and input.GetOptionText then
                    local id = input:GetSelectedID()
                    if id and id > 0 then
                        chosen = input:GetOptionText(id)
                    end
                end
                chosen = chosen or (input.GetValue and input:GetValue()) or ""
                payload[field.key] = chosen
            else
                local val = (input.GetValue and input:GetValue()) or (input.GetText and input:GetText()) or ""
                payload[field.key] = val
            end
        end
        local json = util.TableToJSON(payload, false, true) or ""
        net.Start(NET.Submit)
        net.WriteUInt(#json, 17)
        net.WriteData(json, #json)
        net.SendToServer()
        frame:Close()
    end
end

local function openStatus(app)
    if IsValid(state.statusFrame) then state.statusFrame:Close() end
    local data = util.JSONToTable(app.data_json or "{}") or {}
    local frame = vgui.Create("DFrame")
    frame:SetSize(520, 620)
    frame:Center()
    frame:SetTitle("Ausreiseantrag - Status")
    frame:MakePopup()
    state.statusFrame = frame

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)

    local lbl = vgui.Create("DLabel", scroll)
    lbl:Dock(TOP)
    lbl:SetWrap(true)
    lbl:SetTall(40)
    lbl:SetText("Status: " .. (cfg.Text.StatusNames[app.status] or app.status or "?"))

    for _, field in ipairs(state.lastFields or {}) do
        local val = data[field.key]
        local pnl = vgui.Create("DPanel", scroll)
        pnl:Dock(TOP)
        pnl:DockMargin(0, 0, 0, 6)
        pnl:SetTall(50)
        pnl:SetPaintBackground(false)

        local lbl2 = vgui.Create("DLabel", pnl)
        lbl2:SetPos(0, 0)
        lbl2:SetText(field.label or field.key or "")
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

local function handleData(openFlag)
    if state.lastApp then
        if openFlag or IsValid(state.statusFrame) then
            openStatus(state.lastApp)
        end
    else
        if openFlag then
            openForm()
        elseif IsValid(state.formFrame) then
            -- Benutzer tippt gerade; nicht überschreiben, wenn kein explizites Öffnen gewünscht ist.
        end
    end
end

net.Receive(NET.Data, function()
    local has = net.ReadBool()
    local shouldOpen = net.ReadBool()
    if has then
        state.lastApp = {
            id = net.ReadUInt(32),
            status = net.ReadString(),
            submitted_at = net.ReadString(),
            decided_at = net.ReadString(),
            valid_until = net.ReadString(),
            data_json = net.ReadString(),
        }
    else
        state.lastApp = nil
    end
    ensureFields(net.ReadTable())
    handleData(shouldOpen)
end)

concommand.Add("ausreise_open", function()
    net.Start(NET.Open)
    net.SendToServer()
end)

concommand.Add("ausreise_open_caseworker", function()
    net.Start(NET.OpenCaseworker)
    net.SendToServer()
end)

concommand.Add("ausreise_open_player", function()
    net.Start(NET.OpenPlayer)
    net.SendToServer()
end)

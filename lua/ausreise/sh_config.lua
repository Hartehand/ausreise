-- Ausreiseantrag-System Konfiguration
-- Passe diese Datei an deinen Server an.

Ausreise = Ausreise or {}
Ausreise.Config = Ausreise.Config or {}

local cfg = Ausreise.Config

-- Datenbankeinstellungen
cfg.Database = {
    adapter = "mysqloo", -- "mysqloo" bevorzugt, "tmysql4" als Fallback
    host = "127.0.0.1",
    username = "gmod",
    password = "secret",
    database = "ausreise",
    port = 3306,
    -- optional: setze true, wenn Tabellen beim Start automatisch erstellt werden sollen
    autoCreate = true,
}

-- Erlaube nach finaler Entscheidung einen neuen Antrag nach X Tagen.
-- false oder nil deaktiviert dies (Default: kein neuer Antrag möglich).
cfg.AllowResubmitAfterDays = false

-- Stimmenmodus: "per_team" (genau eine Stimme pro Team) oder "per_player" (jeder Sachbearbeiter darf eine Stimme abgeben)
cfg.VoteMode = "per_team"

-- Benachrichtigungsintervall in Sekunden für Sachbearbeiter
cfg.NotificationInterval = 300

-- Sachbearbeiter-Teams (genau 5 Einträge)
cfg.CaseworkerTeams = {
    TEAM_STAATSSICHERHEIT or TEAM_STASI,
    TEAM_GRENZE,
    TEAM_INNERE,
    TEAM_VERWALTUNG,
    TEAM_MINISTERIUM,
}

-- Teams, die das Terminal verwenden dürfen
cfg.TerminalAccessTeams = {
    TEAM_GRENZE,
    TEAM_INNERE,
    TEAM_STAATSSICHERHEIT or TEAM_STASI,
}

-- Fragen / Felder für den Antrag
-- Typen: text, multiline, number, date, dropdown, checkbox
cfg.Fields = {
    {
        key = "valid_until",
        label = "Gültig bis",
        helper = "Datum, bis wann der Antrag gelten soll (JJJJ-MM-TT).",
        type = "date",
        required = true,
    },
    {
        key = "reason",
        label = "Begründung",
        helper = "Beschreibe, warum du ausreisen möchtest.",
        type = "multiline",
        required = true,
        maxLen = 2048,
    },
    {
        key = "zielort",
        label = "Zielort",
        helper = "Wohin möchtest du reisen?",
        type = "text",
        required = true,
        maxLen = 255,
    },
    {
        key = "begleitung",
        label = "Reist du mit Begleitung?",
        helper = "",
        type = "checkbox",
        required = false,
    },
    {
        key = "transport",
        label = "Transportmittel",
        helper = "",
        type = "dropdown",
        required = true,
        options = {"Zug", "Auto", "Flugzeug", "Zu Fuß"},
    },
    {
        key = "kosten",
        label = "Geschätzte Kosten (DM)",
        helper = "",
        type = "number",
        required = false,
        max = 100000,
    },
}

-- UI Texte
cfg.Text = {
    StatusNames = {
        submitted = "Antrag gestellt",
        in_progress = "In Bearbeitung",
        approved = "Ausreise genehmigt",
        denied = "Ausreise abgelehnt",
    }
}

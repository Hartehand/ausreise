Ausreise = Ausreise or {}
Ausreise.Net = Ausreise.Net or {}

local function registerStrings()
    for _, name in pairs(Ausreise.Net) do
        if isstring(name) then
            util.AddNetworkString(name)
        end
    end
end

registerStrings()

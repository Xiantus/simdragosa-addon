-- =============================================================================
-- Simdragosa — WoW tooltip addon
-- Shows Droptimizer DPS gains (from the Simdragosa sim tool) in item tooltips.
--
-- Data source: SimdragosaData.lua in the addon folder, written by the Simdragosa web app.
--              WoW loads this file on every /reload — no logout required.
-- Repo:        https://github.com/Xiantus/simdragosa-addon
-- =============================================================================

local ADDON = "Simdragosa"

-- ---------------------------------------------------------------------------
-- Default config
-- ---------------------------------------------------------------------------

local DEFAULTS = {
    enabled        = true,
    stalenessDays  = 30,   -- hide entries older than this many days
    showStaleness  = true, -- show "Simmed: N days ago" line
}

-- ---------------------------------------------------------------------------
-- Colour palette (matches the Simdragosa web app theme)
-- ---------------------------------------------------------------------------

local C = {
    high   = "|cff4ade80",  -- green  — large gain
    medium = "|cfffbbf24",  -- yellow — moderate gain
    low    = "|cff7878a0",  -- grey   — small gain
    label  = "|cff9a8cff",  -- purple — "Simdragosa" label
    stale  = "|cff7878a0",  -- grey   — staleness note
    green  = "|cff4ade80",  -- green  — positive debug output
    red    = "|cfff87171",  -- red    — error/missing debug output
    hi     = "|cfffbbf24",  -- yellow — highlighted values in debug output
    reset  = "|r",
}

-- DPS thresholds for colour coding
local THRESHOLD_HIGH   = 1500
local THRESHOLD_MEDIUM = 400

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function GetCharKey()
    local name  = UnitName("player") or ""
    local realm = GetRealmName() or ""
    return name .. "-" .. realm:gsub("%s+", "")
end

local function ColourForDPS(dps)
    if dps >= THRESHOLD_HIGH   then return C.high   end
    if dps >= THRESHOLD_MEDIUM then return C.medium end
    return C.low
end

local function FormatDPS(dps)
    if dps >= 1000 then
        return string.format("%.1fk", dps / 1000)
    end
    return string.format("%.0f", dps)
end

-- Returns days since dateStr ("YYYY-MM-DD"), or nil if unparseable.
local function DaysSince(dateStr)
    if not dateStr or dateStr == "" then return nil end
    local y, m, d = dateStr:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y then return nil end
    local then_time = time({ year=tonumber(y), month=tonumber(m), day=tonumber(d),
                             hour=0, min=0, sec=0 })
    return math.floor((time() - then_time) / 86400)
end

local function FormatStaleness(dateStr)
    local days = DaysSince(dateStr)
    if not days then return nil end
    if days == 0 then return "today" end
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= ADDON then return end

    -- Merge saved config with defaults
    SimdragosaConfig = SimdragosaConfig or {}
    for k, v in pairs(DEFAULTS) do
        if SimdragosaConfig[k] == nil then
            SimdragosaConfig[k] = v
        end
    end

    -- SimdragosaDB is populated by SimdragosaData.lua (loaded before this file).
    -- Fall back to empty table if the data file doesn't exist yet.
    SimdragosaDB = SimdragosaDB or {}
end)

-- ---------------------------------------------------------------------------
-- Tooltip hook
-- ---------------------------------------------------------------------------

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    -- Bail early if disabled or DB not loaded
    if not SimdragosaConfig or not SimdragosaConfig.enabled then return end
    if not SimdragosaDB then return end

    local itemID = data.id
    if not itemID or itemID == 0 then return end

    local charKey  = GetCharKey()
    local charData = SimdragosaDB[charKey]
    if not charData then return end

    local entry = charData[itemID]
    if not entry then return end

    -- Staleness check
    local days = DaysSince(entry.updated)
    if days and SimdragosaConfig.stalenessDays > 0
             and days > SimdragosaConfig.stalenessDays then
        return
    end

    -- Build DPS gain lines — one per spec, showing all available tracks inline
    local gainLines = {}

    local specs = entry.specs
    if specs then
        for _, specData in ipairs(specs) do
            -- Collect per-track gains for this spec
            local diffParts = {}
            if specData.champion and specData.champion > 0 then
                local col = ColourForDPS(specData.champion)
                diffParts[#diffParts + 1] = string.format("%s+%s DPS%s %s(Champ)%s",
                    col, FormatDPS(specData.champion), C.reset, C.low, C.reset)
            end
            if specData.heroic and specData.heroic > 0 then
                local col = ColourForDPS(specData.heroic)
                diffParts[#diffParts + 1] = string.format("%s+%s DPS%s %s(Heroic)%s",
                    col, FormatDPS(specData.heroic), C.reset, C.low, C.reset)
            end
            if specData.mythic and specData.mythic > 0 then
                local col = ColourForDPS(specData.mythic)
                diffParts[#diffParts + 1] = string.format("%s+%s DPS%s %s(Mythic)%s",
                    col, FormatDPS(specData.mythic), C.reset, C.low, C.reset)
            end

            if #diffParts > 0 then
                local diffStr = table.concat(diffParts, "  ")
                local specName = specData.spec or ""
                if specName ~= "" then
                    gainLines[#gainLines + 1] = string.format("%s[%s]%s  %s",
                        C.label, specName, C.reset, diffStr)
                else
                    -- Legacy data (no spec recorded) — show gains without label
                    gainLines[#gainLines + 1] = diffStr
                end
            end
        end
    end

    if #gainLines == 0 then return end

    -- Inject into tooltip
    tooltip:AddLine(" ")  -- visual spacer
    for _, line in ipairs(gainLines) do
        tooltip:AddLine(line)
    end

    -- Staleness footer
    if SimdragosaConfig.showStaleness then
        local when = FormatStaleness(entry.updated)
        if when then
            tooltip:AddLine(string.format(
                "%s%s — simmed %s%s",
                C.label, ADDON, when, C.reset
            ))
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_SIMDRAGOSA1 = "/simdragosa"
SLASH_SIMDRAGOSA2 = "/sdr"

SlashCmdList["SIMDRAGOSA"] = function(msg)
    local cmd = msg:lower():match("^%s*(%S+)")

    if cmd == "toggle" then
        SimdragosaConfig.enabled = not SimdragosaConfig.enabled
        local state = SimdragosaConfig.enabled and "enabled" or "disabled"
        print(C.label .. ADDON .. C.reset .. ": tooltip lines " .. state .. ".")

    elseif cmd == "status" then
        local charKey  = GetCharKey()
        local charData = SimdragosaDB and SimdragosaDB[charKey]
        if not charData then
            print(C.label .. ADDON .. C.reset .. ": no sim data found for " .. charKey .. ".")
            return
        end
        local count = 0
        local latest = ""
        for _, info in pairs(charData) do
            count = count + 1
            if info.updated and info.updated > latest then
                latest = info.updated
            end
        end
        print(string.format(
            "%s%s%s: %d items stored for %s. Last sim: %s.",
            C.label, ADDON, C.reset, count, charKey,
            latest ~= "" and latest or "unknown"
        ))

    elseif cmd == "staleness" then
        local n = tonumber(msg:match("%d+"))
        if n then
            SimdragosaConfig.stalenessDays = n
            print(C.label .. ADDON .. C.reset .. ": hiding entries older than " .. n .. " days.")
        else
            print(C.label .. ADDON .. C.reset .. ": usage: /sdr staleness <days>  (0 = never hide)")
        end

    elseif cmd == "debug" then
        local charKey = GetCharKey()
        print(C.label .. "── Simdragosa debug ──" .. C.reset)
        print("  Character key : " .. C.hi .. charKey .. C.reset)
        print("  Config enabled: " .. tostring(SimdragosaConfig and SimdragosaConfig.enabled))

        -- DB overview
        if not SimdragosaDB or next(SimdragosaDB) == nil then
            print("  " .. C.red .. "SimdragosaDB is empty — no sims have been stored yet." .. C.reset)
            print("  Run a Droptimizer sim in Simdragosa, then /reload.")
            return
        end

        -- List all character keys present in the DB
        local keys = {}
        for k in pairs(SimdragosaDB) do keys[#keys+1] = k end
        print("  DB has entries for " .. #keys .. " character(s):")
        for _, k in ipairs(keys) do
            local count = 0
            for _ in pairs(SimdragosaDB[k]) do count = count + 1 end
            local match = (k == charKey) and C.green .. " ◄ you" .. C.reset or ""
            print(string.format("    %s%s%s — %d items%s", C.hi, k, C.reset, count, match))
        end

        -- Check a specific item ID if provided
        local itemArg = tonumber(msg:match("%d+"))
        if itemArg then
            local charData = SimdragosaDB[charKey]
            if charData and charData[itemArg] then
                local e = charData[itemArg]
                print(string.format("  Item %d%s found%s:", itemArg, C.green, C.reset))
                if e.ilvl    then print(string.format("    ilvl    = %d",  e.ilvl))    end
                if e.name    then print(string.format("    name    = %s",  e.name))    end
                if e.updated then print(string.format("    updated = %s",  e.updated)) end
                if e.specs then
                    for _, sd in ipairs(e.specs) do
                        local specLabel = (sd.spec and sd.spec ~= "") and sd.spec or "?"
                        local parts = {}
                        if sd.champion then parts[#parts+1] = string.format("champ=%.1f", sd.champion) end
                        if sd.heroic   then parts[#parts+1] = string.format("heroic=%.1f", sd.heroic)  end
                        if sd.mythic   then parts[#parts+1] = string.format("mythic=%.1f", sd.mythic)  end
                        print(string.format("    [%s]  %s", specLabel, table.concat(parts, "  ")))
                    end
                end
            else
                print(string.format("  Item %d%s not found%s for %s.",
                    itemArg, C.red, C.reset, charKey))
                print("  Either it wasn't in the Droptimizer results, or the sim hasn't run yet.")
            end
        end

    else
        print(C.label .. ADDON .. C.reset .. " commands:")
        print("  /sdr toggle            — show/hide tooltip lines")
        print("  /sdr status            — show stored item count for your character")
        print("  /sdr staleness <n>     — hide sims older than N days (0 = never)")
        print("  /sdr debug             — show DB contents and character key")
        print("  /sdr debug <itemID>    — check if a specific item ID has sim data")
    end
end

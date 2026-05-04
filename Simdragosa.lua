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
    minimapHidden  = false,
    minimapAngle   = nil,  -- radians; nil = default position
    lastSource     = nil,  -- persisted source filter
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

local HEALER_SPECS = {
    discipline=true, holy=true, restoration=true,
    mistweaver=true, preservation=true,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function GetCharKey()
    local name  = UnitName("player") or ""
    local realm = GetRealmName() or ""
    return name .. "-" .. realm:gsub("%s+", "")
end

-- Case-insensitive DB lookup: standalone may save realm in lowercase.
local function GetCharData(key)
    if not SimdragosaDB then return nil end
    if SimdragosaDB[key] then return SimdragosaDB[key] end
    local keyLower = key:lower()
    for k, v in pairs(SimdragosaDB) do
        if k:lower() == keyLower then return v end
    end
    return nil
end

local function CharKeyMatches(dbKey, charKey)
    return dbKey == charKey or dbKey:lower() == charKey:lower()
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
    if addonName == ADDON then
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

        -- Build the results window now that config is initialised.
        RW_CreateFrame()
        RW_CreateMinimapButton()

        -- Restore saved window position.
        if SimdragosaConfig.windowPos and SimdragosaResultsFrame then
            local p = SimdragosaConfig.windowPos
            SimdragosaResultsFrame:ClearAllPoints()
            SimdragosaResultsFrame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end

        -- Try hooking the SimC slash command now (works if SimC loaded before us)
        -- and register to try again if SimC loads after us.
        SIMC_HookFrame()

    else
        -- Any other addon finishing load — try hooking in case it's SimC
        -- (covers different folder names / load-order variations).
        if not simcHooked then SIMC_HookFrame() end
    end
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
    local charData = GetCharData(charKey)
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

    local function addDiffParts(src, specLabel)
        local gainLabel = HEALER_SPECS[specLabel] and "HPS" or "DPS"
        local diffParts = {}
        if src.champion and src.champion > 0 then
            local col = ColourForDPS(src.champion)
            diffParts[#diffParts + 1] = string.format("%s+%s %s%s %s(Champ)%s",
                col, FormatDPS(src.champion), gainLabel, C.reset, C.low, C.reset)
        end
        if src.heroic and src.heroic > 0 then
            local col = ColourForDPS(src.heroic)
            diffParts[#diffParts + 1] = string.format("%s+%s %s%s %s(Heroic)%s",
                col, FormatDPS(src.heroic), gainLabel, C.reset, C.low, C.reset)
        end
        if src.mythic and src.mythic > 0 then
            local col = ColourForDPS(src.mythic)
            diffParts[#diffParts + 1] = string.format("%s+%s %s%s %s(Mythic)%s",
                col, FormatDPS(src.mythic), gainLabel, C.reset, C.low, C.reset)
        end
        if #diffParts > 0 then
            local diffStr = table.concat(diffParts, "  ")
            if specLabel and specLabel ~= "" then
                gainLines[#gainLines + 1] = string.format("%s[%s]%s  %s",
                    C.label, specLabel, C.reset, diffStr)
            else
                gainLines[#gainLines + 1] = diffStr
            end
        end
    end

    if not entry.specs then return end
    for _, specData in ipairs(entry.specs) do
        if specData.spec and specData.spec ~= "" then
            addDiffParts(specData, specData.spec)
        end
    end

    if #gainLines == 0 then return end

    -- Inject into tooltip
    tooltip:AddLine(" ")  -- visual spacer
    for _, line in ipairs(gainLines) do
        tooltip:AddLine(line)
    end

    -- Staleness footer + /sdr hint
    if SimdragosaConfig.showStaleness then
        local when = FormatStaleness(entry.updated)
        if when then
            tooltip:AddLine(string.format(
                "%s%s — simmed %s  %s·  /sdr results%s",
                C.label, ADDON, when, C.stale, C.reset
            ))
        else
            tooltip:AddLine(C.label .. ADDON .. C.reset
                .. "  " .. C.stale .. "·  /sdr results" .. C.reset)
        end
    else
        tooltip:AddLine(C.label .. ADDON .. C.reset
            .. "  " .. C.stale .. "·  /sdr results" .. C.reset)
    end
end)

-- ---------------------------------------------------------------------------
-- Results Window
-- ---------------------------------------------------------------------------

local RW_W      = 420    -- frame width
local RW_H      = 500    -- frame height
local RW_ROW_H  = 28     -- row height (two-line layout)
local RW_ICON_W = 18     -- item icon size
local RW_NAME_W = 140    -- item name column width
local RW_BAR_X  = 168    -- bar start X (icon + name + gaps)
local RW_BAR_W  = 148    -- DPS bar max width
local RW_DPS_W  = 62     -- DPS value column width

-- Rank-relative bar colours: 1st=legendary, 2nd=epic, 3rd=rare, 4th=uncommon, 5th+=grey
local RW_RANK_COLORS = {
    {0.99, 0.50, 0.00},  -- 1st: legendary orange
    {0.64, 0.21, 0.93},  -- 2nd: epic purple
    {0.00, 0.44, 0.87},  -- 3rd: rare blue
    {0.12, 0.93, 0.00},  -- 4th: uncommon green
    {0.62, 0.62, 0.62},  -- 5th+: grey
}
local function RW_RankColor(rank)
    return RW_RANK_COLORS[math.min(rank, #RW_RANK_COLORS)]
end

local RW_TRACK_LABELS = { champion = "Champion", heroic = "Heroic", mythic = "Mythic" }
local RW_TRACK_ORDER  = { "champion", "heroic", "mythic" }

-- Static zone-ID → name table for Midnight Season 1 dungeons.
-- Keys are Wowhead zone/area IDs; updated each season.
-- Used as last-resort fallback when dynamic WoW APIs return nothing.
local RW_ZONE_NAMES = {
    -- Midnight Season 1 — new dungeons
    [15829] = "Magisters' Terrace",
    [16395] = "Maisara Caverns",
    [16573] = "Nexus-Point Xenas",
    [15808] = "Windrunner Spire",
    -- Midnight Season 1 — legacy dungeons
    [14032] = "Algeth'ar Academy",
    [8910]  = "The Seat of the Triumvirate",
    [6988]  = "Skyreach",
    [4813]  = "Pit of Saron",
}

-- Challenge mode map cache: built once on RW_CreateFrame, covers current M+ season.
-- Keys are challenge mode map IDs (different from zone IDs above).
local RW_CHALLENGE_MAP_NAMES = {}

-- rw holds all mutable state for the results window.
local rw = {
    frame       = nil,
    content     = nil,
    rows        = {},   -- pool of reusable row sub-frames
    titleLabel  = nil,  -- dynamic header: char name + upgrade count
    specLabel   = nil,
    trackLabel  = nil,
    sourceBtn   = nil,   -- dropdown toggle button text label
    sourcePopup = nil,   -- dropdown popup frame
    sourceBtns  = {},    -- reusable button pool inside popup
    footer      = nil,
    charKey     = nil,
    specList    = {},
    specIdx     = 1,
    trackList   = {},
    trackIdx    = 1,
    sourceList  = {},
    sourceIdx   = 1,
}

-- ── Data helpers ──────────────────────────────────────────────────────────────

local function RW_GetSpecs(charKey)
    if not SimdragosaDB then return {} end
    local charData = GetCharData(charKey)
    if not charData then return {} end
    local seen, list = {}, {}
    for _, entry in pairs(charData) do
        if entry.specs then
            for _, sd in ipairs(entry.specs) do
                local s = sd.spec and sd.spec:lower() or ""
                if s ~= "" and not seen[s] then
                    seen[s] = true; list[#list + 1] = s
                end
            end
        end
    end
    table.sort(list)
    return list
end

local function RW_GetTracks(charKey, spec)
    if not SimdragosaDB then return {} end
    local charData = GetCharData(charKey)
    if not charData then return {} end
    local seen = {}
    for _, entry in pairs(charData) do
        if entry.specs then
            for _, sd in ipairs(entry.specs) do
                local sdSpec = sd.spec and sd.spec:lower() or ""
                if spec == nil or sdSpec == spec then
                    for _, t in ipairs(RW_TRACK_ORDER) do
                        if sd[t] and sd[t] > 0 then seen[t] = true end
                    end
                end
            end
        end
    end
    local tracks = {}
    for _, t in ipairs(RW_TRACK_ORDER) do
        if seen[t] then tracks[#tracks + 1] = t end
    end
    return tracks
end

local function RW_GetSources(charKey)
    if not SimdragosaDB then return {""} end
    local charData = GetCharData(charKey)
    if not charData then return {""} end
    local hasRaids = false
    local dungeons, seenDungeons = {}, {}
    for _, entry in pairs(charData) do
        local src   = entry.source     or ""
        local stype = entry.sourceType or ""
        -- Raids: only track presence — Raidbots puts boss encounter IDs in
        -- source for raid items, which we don't want as individual filter tabs.
        if stype == "raid" then
            hasRaids = true
        elseif stype == "dungeon" and src ~= "" and not seenDungeons[src] then
            seenDungeons[src] = true; dungeons[#dungeons + 1] = src
        end
    end
    table.sort(dungeons)
    local list = {""}  -- "" = All Sources
    if hasRaids then
        list[#list + 1] = "__raids__"
    end
    if #dungeons > 0 then
        list[#list + 1] = "__dungeons__"
        for _, d in ipairs(dungeons) do list[#list + 1] = d end
    end
    return list
end

local function RW_SourceDisplay(src)
    if not src or src == ""  then return "All Sources"  end
    if src == "__raids__"    then return "All Raids"    end
    if src == "__dungeons__" then return "All Dungeons" end
    local numId = tonumber(src)
    if numId then
        -- 1. Encounter Journal instance name (raids + dungeons by EJ ID)
        if EJ_GetInstanceInfo then
            local name = EJ_GetInstanceInfo(numId)
            if name and name ~= "" then return name end
        end
        -- 2. Challenge mode map cache (built at startup from current M+ season)
        if RW_CHALLENGE_MAP_NAMES[numId] then return RW_CHALLENGE_MAP_NAMES[numId] end
        -- 3. WoW area/zone info (same ID system as Wowhead zone= URLs)
        if C_Map and C_Map.GetAreaInfo then
            local name = C_Map.GetAreaInfo(numId)
            if name and name ~= "" then return name end
        end
        -- 4. WoW UI map info (broader map record system)
        if C_Map and C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(numId)
            if info and info.name and info.name ~= "" then return info.name end
        end
        -- 5. Static fallback table (Midnight S1 zone IDs)
        if RW_ZONE_NAMES[numId] then return RW_ZONE_NAMES[numId] end
    end
    return src
end

local function RW_BuildList(charKey, spec, track, source)
    if not SimdragosaDB or not track then return {} end
    local charData = GetCharData(charKey)
    if not charData then return {} end
    local list = {}
    local srcFilter     = (source and source ~= "" and source ~= "__raids__" and source ~= "__dungeons__") and source or nil
    local srcTypeFilter = (source == "__raids__" and "raid") or (source == "__dungeons__" and "dungeon") or nil
    for itemID, entry in pairs(charData) do
        local srcOK = true
        if srcFilter     and (entry.source     or "") ~= srcFilter     then srcOK = false end
        if srcTypeFilter and (entry.sourceType or "") ~= srcTypeFilter then srcOK = false end
        if srcOK then
            local bestDPS = nil
            if entry.specs then
                for _, sd in ipairs(entry.specs) do
                    local sdSpec = sd.spec and sd.spec:lower() or ""
                    if (spec == nil or sdSpec == spec) and sd[track] and sd[track] > 0 then
                        if bestDPS == nil or sd[track] > bestDPS then
                            bestDPS = sd[track]
                        end
                    end
                end
            end
            if bestDPS then
                list[#list + 1] = {
                    itemID  = tonumber(itemID),
                    name    = entry.name or ("Item #" .. tostring(itemID)),
                    dps     = bestDPS,
                    ilvl    = entry.ilvl,
                    track   = track,
                    updated = entry.updated,
                    icon    = entry.icon,
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.dps > b.dps end)
    return list
end

-- ── Scaled tooltip helpers ────────────────────────────────────────────────────

-- ilvl delta → bonus ID (adds N levels to base item ilvl in the client).
-- Sourced from KeystoneLoot addon (Wolkenschutz/KeystoneLoot on GitHub).
-- These are universal client DB2 bonus IDs — work for any item.
local ILVL_DELTA_BONUS = {
    [-100]=1372,[-99]=1373,[-98]=1374,[-97]=1375,[-96]=1376,[-95]=1377,[-94]=1378,[-93]=1379,[-92]=1380,[-91]=1381,[-90]=1382,[-89]=1383,[-88]=1384,[-87]=1385,[-86]=1386,[-85]=1387,[-84]=1388,[-83]=1389,[-82]=1390,[-81]=1391,[-80]=1392,[-79]=1393,[-78]=1394,[-77]=1395,[-76]=1396,[-75]=1397,[-74]=1398,[-73]=1399,[-72]=1400,[-71]=1401,[-70]=1402,[-69]=1403,[-68]=1404,[-67]=1405,[-66]=1406,[-65]=1407,[-64]=1408,[-63]=1409,[-62]=1410,[-61]=1411,[-60]=1412,[-59]=1413,[-58]=1414,[-57]=1415,[-56]=1416,[-55]=1417,[-54]=1418,[-53]=1419,[-52]=1420,[-51]=1421,[-50]=1422,[-49]=1423,[-48]=1424,[-47]=1425,[-46]=1426,[-45]=1427,[-44]=1428,[-43]=1429,[-42]=1430,[-41]=1431,[-40]=1432,[-39]=1433,[-38]=1434,[-37]=1435,[-36]=1436,[-35]=1437,[-34]=1438,[-33]=1439,[-32]=1440,[-31]=1441,[-30]=1442,[-29]=1443,[-28]=1444,[-27]=1445,[-26]=1446,[-25]=1447,[-24]=1448,[-23]=1449,[-22]=1450,[-21]=1451,[-20]=1452,[-19]=1453,[-18]=1454,[-17]=1455,[-16]=1456,[-15]=1457,[-14]=1458,[-13]=1459,[-12]=1460,[-11]=1461,[-10]=1462,[-9]=1463,[-8]=1464,[-7]=1465,[-6]=1466,[-5]=1467,[-4]=1468,[-3]=1469,[-2]=1470,[-1]=1471,
    [1]=1473,[2]=1474,[3]=1475,[4]=1476,[5]=1477,[6]=1478,[7]=1479,[8]=1480,[9]=1481,[10]=1482,[11]=1483,[12]=1484,[13]=1485,[14]=1486,[15]=1487,[16]=1488,[17]=1489,[18]=1490,[19]=1491,[20]=1492,[21]=1493,[22]=1494,[23]=1495,[24]=1496,[25]=1497,[26]=1498,[27]=1499,[28]=1500,[29]=1501,[30]=1502,[31]=1503,[32]=1504,[33]=1505,[34]=1506,[35]=1507,[36]=1508,[37]=1509,[38]=1510,[39]=1511,[40]=1512,[41]=1513,[42]=1514,[43]=1515,[44]=1516,[45]=1517,[46]=1518,[47]=1519,[48]=1520,[49]=1521,[50]=1522,[51]=1523,[52]=1524,[53]=1525,[54]=1526,[55]=1527,[56]=1528,[57]=1529,[58]=1530,[59]=1531,[60]=1532,[61]=1533,[62]=1534,[63]=1535,[64]=1536,[65]=1537,[66]=1538,[67]=1539,[68]=1540,[69]=1541,[70]=1542,[71]=1543,[72]=1544,[73]=1545,[74]=1546,[75]=1547,[76]=1548,[77]=1549,[78]=1550,[79]=1551,[80]=1552,[81]=1553,[82]=1554,[83]=1555,[84]=1556,[85]=1557,[86]=1558,[87]=1559,[88]=1560,[89]=1561,[90]=1562,[91]=1563,[92]=1564,[93]=1565,[94]=1566,[95]=1567,[96]=1568,[97]=1569,[98]=1570,[99]=1571,[100]=1572,
    [101]=1573,[102]=1574,[103]=1575,[104]=1576,[105]=1577,[106]=1578,[107]=1579,[108]=1580,[109]=1581,[110]=1582,[111]=1583,[112]=1584,[113]=1585,[114]=1586,[115]=1587,[116]=1588,[117]=1589,[118]=1590,[119]=1591,[120]=1592,[121]=1593,[122]=1594,[123]=1595,[124]=1596,[125]=1597,[126]=1598,[127]=1599,[128]=1600,[129]=1601,[130]=1602,[131]=1603,[132]=1604,[133]=1605,[134]=1606,[135]=1607,[136]=1608,[137]=1609,[138]=1610,[139]=1611,[140]=1612,[141]=1613,[142]=1614,[143]=1615,[144]=1616,[145]=1617,[146]=1618,[147]=1619,[148]=1620,[149]=1621,[150]=1622,[151]=1623,[152]=1624,[153]=1625,[154]=1626,[155]=1627,[156]=1628,[157]=1629,[158]=1630,[159]=1631,[160]=1632,[161]=1633,[162]=1634,[163]=1635,[164]=1636,[165]=1637,[166]=1638,[167]=1639,[168]=1640,[169]=1641,[170]=1642,[171]=1643,[172]=1644,[173]=1645,[174]=1646,[175]=1647,[176]=1648,[177]=1649,[178]=1650,[179]=1651,[180]=1652,[181]=1653,[182]=1654,[183]=1655,[184]=1656,[185]=1657,[186]=1658,[187]=1659,[188]=1660,[189]=1661,[190]=1662,[191]=1663,[192]=1664,[193]=1665,[194]=1666,[195]=1667,[196]=1668,[197]=1669,[198]=1670,[199]=1671,[200]=1672,
    [201]=3130,[202]=3131,[203]=3132,[204]=3133,[205]=3134,[206]=3135,[207]=3136,[208]=3137,[209]=3138,[210]=3139,[211]=3140,[212]=3141,[213]=3142,[214]=3143,[215]=3144,[216]=3145,[217]=3146,[218]=3147,[219]=3148,[220]=3149,[221]=3150,[222]=3151,[223]=3152,[224]=3153,[225]=3154,[226]=3155,[227]=3156,[228]=3157,[229]=3158,[230]=3159,[231]=3160,[232]=3161,[233]=3162,[234]=3163,[235]=3164,[236]=3165,[237]=3166,[238]=3167,[239]=3168,[240]=3169,[241]=3170,[242]=3171,[243]=3172,[244]=3173,[245]=3174,[246]=3175,[247]=3176,[248]=3177,[249]=3178,[250]=3179,[251]=3180,[252]=3181,[253]=3182,[254]=3183,[255]=3184,[256]=3185,[257]=3186,[258]=3187,[259]=3188,[260]=3189,[261]=3190,[262]=3191,[263]=3192,[264]=3193,[265]=3194,[266]=3195,[267]=3196,[268]=3197,[269]=3198,[270]=3199,[271]=3200,[272]=3201,[273]=3202,[274]=3203,[275]=3204,[276]=3205,[277]=3206,[278]=3207,[279]=3208,[280]=3209,[281]=3210,[282]=3211,[283]=3212,[284]=3213,[285]=3214,[286]=3215,[287]=3216,[288]=3217,[289]=3218,[290]=3219,[291]=3220,[292]=3221,[293]=3222,[294]=3223,[295]=3224,[296]=3225,[297]=3226,[298]=3227,[299]=3228,[300]=3229,
}

-- Midnight S1: track → max (6/6) ilvl and its bonus ID.
-- entry.ilvl in the Lua export is always the item's actual equipped ilvl (mythic cap),
-- so we override per-track to show the correct tier in the tooltip.
-- UPDATE EACH SEASON.
local TRACK_DISPLAY = {
    lfr      = { ilvl = 250, bonusId = 12782 },
    normal   = { ilvl = 263, bonusId = 12790 },
    heroic   = { ilvl = 276, bonusId = 12798 },
    mythic   = { ilvl = 289, bonusId = 12806 },
    champion = { ilvl = 263, bonusId = 12790 },
}

-- Build a scaled item link (same technique as KeystoneLoot addon).
-- entry.ilvl is always the item's actual equipped ilvl (mythic cap), so we ignore it
-- and derive the correct display ilvl from the track via TRACK_DISPLAY.
-- Returns nil if base ilvl unavailable (not cached yet); caller falls back to SetItemByID.
local function BuildScaledItemLink(itemID, track)
    local td = track and TRACK_DISPLAY[track]
    if not td then return nil end

    local _, _, baseIlvl = C_Item.GetDetailedItemLevelInfo(itemID)
    if not baseIlvl or baseIlvl == 0 then return nil end

    local delta = td.ilvl - baseIlvl
    local deltaBonus = ILVL_DELTA_BONUS[delta]
    if not deltaBonus then return nil end

    local playerLevel = UnitLevel("player") or 80
    local specId = 0
    local curSlot = GetSpecialization()
    if curSlot then specId = select(1, GetSpecializationInfo(curSlot)) or 0 end

    -- delta bonus (stat scaling) + track tier bonus (upgrade label) + 1674 (epic quality)
    return string.format("item:%d::::::::%d:%d:::3:%d:%d:1674",
        itemID, playerLevel, specId, deltaBonus, td.bonusId)
end

-- ── Row helpers ───────────────────────────────────────────────────────────────

local function RW_FormatDPS(dps)
    if dps >= 1000 then return string.format("+%.1fk", dps / 1000) end
    return string.format("+%.0f", dps)
end

local function RW_GetOrCreateRow(idx)
    if rw.rows[idx] then return rw.rows[idx] end

    local row = CreateFrame("Button", nil, rw.content)
    row:SetHeight(RW_ROW_H)
    row:SetPoint("LEFT",  rw.content, "LEFT",  0, 0)
    row:SetPoint("RIGHT", rw.content, "RIGHT", -4, 0)

    -- Alternating row tint
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    -- Item icon (hover shows full tooltip)
    local iconTex = row:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("LEFT", row, "LEFT", 4, 0)
    iconTex:SetSize(RW_ICON_W, RW_ICON_W)
    iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.iconTex = iconTex

    -- Item name (top line)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", RW_ICON_W + 8, -4)
    nameText:SetWidth(RW_NAME_W)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    -- Track/ilvl sub-line (bottom)
    local subText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subText:SetPoint("TOPLEFT", row, "TOPLEFT", RW_ICON_W + 8, -17)
    subText:SetWidth(RW_NAME_W)
    subText:SetJustifyH("LEFT")
    subText:SetWordWrap(false)
    row.subText = subText

    -- DPS bar background (subtle purple tint)
    local barBg = row:CreateTexture(nil, "ARTWORK")
    barBg:SetPoint("LEFT", row, "LEFT", RW_BAR_X, 0)
    barBg:SetSize(RW_BAR_W, 12)
    barBg:SetColorTexture(0.16, 0.10, 0.28, 0.85)
    row.barBg = barBg

    -- DPS bar fill (OVERLAY so it always draws on top of the background)
    local barFill = row:CreateTexture(nil, "OVERLAY")
    barFill:SetPoint("LEFT", row, "LEFT", RW_BAR_X, 0)
    barFill:SetHeight(12)
    barFill:SetWidth(1)
    row.barFill = barFill

    -- DPS value
    local dpsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpsText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    dpsText:SetWidth(RW_DPS_W)
    dpsText:SetJustifyH("RIGHT")
    row.dpsText = dpsText

    -- Tooltip on hover / shift-click to link
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local scaledLink = BuildScaledItemLink(self.itemID, self.simTrack)
            local td = self.simTrack and TRACK_DISPLAY[self.simTrack]
            if scaledLink then
                GameTooltip:SetHyperlink(scaledLink)
                -- Always show which track + ilvl was simmed
                if td then
                    GameTooltip:AddLine(" ")
                    local trackName = RW_TRACK_LABELS[self.simTrack] or self.simTrack or ""
                    GameTooltip:AddDoubleLine(
                        C.label .. "Simdragosa" .. C.reset,
                        "|cff9a8cffSimmed: " .. trackName .. " " .. td.ilvl .. "|r",
                        1, 1, 1, 1, 1, 1
                    )
                    GameTooltip:AddLine(C.low .. "/sdr results to open upgrade window" .. C.reset)
                end
            else
                -- Fallback: base stats + footer note (item not cached or ilvl out of table)
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:AddLine(" ")
                if td then
                    local trackName = RW_TRACK_LABELS[self.simTrack] or self.simTrack or ""
                    GameTooltip:AddDoubleLine(
                        C.label .. "Simdragosa" .. C.reset,
                        "|cff9a8cffSimmed: " .. trackName .. " " .. td.ilvl .. "|r",
                        1, 1, 1, 1, 1, 1
                    )
                elseif self.simIlvl then
                    GameTooltip:AddDoubleLine(
                        C.label .. "Simdragosa" .. C.reset,
                        "|cffffd100Simmed at ilvl " .. self.simIlvl .. "|r",
                        1, 1, 1, 1, 1, 1
                    )
                end
                GameTooltip:AddLine(C.low .. "/sdr results to open upgrade window" .. C.reset)
            end
            GameTooltip:Show()
        end
        self.bg:SetColorTexture(0.25, 0.20, 0.45, 0.5)
    end)
    row:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.oddRow then
            self.bg:SetColorTexture(0.08, 0.08, 0.08, 0.3)
        else
            self.bg:SetColorTexture(0, 0, 0, 0)
        end
    end)
    row:SetScript("OnClick", function(self)
        if self.itemID and IsShiftKeyDown() then
            local _, link = GetItemInfo(self.itemID)
            if link then ChatEdit_InsertLink(link) end
        end
    end)

    rw.rows[idx] = row
    return row
end

-- ── Refresh (re-populates visible rows) ──────────────────────────────────────

local function RW_Refresh()
    if not rw.frame or not rw.frame:IsShown() then return end

    local spec   = rw.specList[rw.specIdx]
    local track  = rw.trackList[rw.trackIdx]
    local source = rw.sourceList[rw.sourceIdx]

    -- Cycle button labels
    local specDisplay   = spec  and (spec:sub(1,1):upper()  .. spec:sub(2))  or "All Specs"
    local trackDisplay  = track and (RW_TRACK_LABELS[track] or track) or "—"
    rw.specLabel:SetText(specDisplay)
    rw.trackLabel:SetText(trackDisplay)
    rw.sourceBtn:SetText(RW_SourceDisplay(source))

    -- Column header: HPS for healer specs, DPS otherwise
    local gainHeader = (spec and HEALER_SPECS[spec]) and "HPS GAIN" or "DPS GAIN"
    rw.hdrGain:SetText(C.low .. gainHeader .. C.reset)

    if not track then
        for _, row in ipairs(rw.rows) do row:Hide() end
        rw.content:SetHeight(20)
        if rw.titleLabel then
            local charName = (rw.charKey:match("^([^%-]+)") or rw.charKey):upper()
            rw.titleLabel:SetText(C.label .. charName .. C.reset .. "  |cff7878a0—|r")
        end
        rw.footer:SetText(C.low .. "No sim data found. Run a sim and /reload." .. C.reset)
        return
    end

    local list   = RW_BuildList(rw.charKey, spec, track, source)

    -- Dynamic title: char name + upgrade count
    if rw.titleLabel then
        local charName = (rw.charKey:match("^([^%-]+)") or rw.charKey):upper()
        rw.titleLabel:SetText(C.label .. charName .. C.reset
            .. "  |cff7878a0" .. #list .. " upgrades|r")
    end
    local maxDPS = (list[1] and list[1].dps) or 1
    local count  = math.min(#list, 40)

    rw.content:SetHeight(math.max(count * RW_ROW_H, 20))

    for i = 1, count do
        local item = list[i]
        local row  = RW_GetOrCreateRow(i)
        row.itemID    = item.itemID
        row.itemName  = item.name
        row.simIlvl   = item.ilvl
        row.simTrack  = item.track
        row.oddRow    = (i % 2 == 1)

        -- Background alternating tint
        if row.oddRow then
            row.bg:SetColorTexture(0.09, 0.07, 0.15, 0.4)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row:SetPoint("TOP", rw.content, "TOP", 0, -(i - 1) * RW_ROW_H)

        -- Icon: C_Item.GetItemIconByID returns the numeric file ID directly from
        -- the client — no cache required, no string path needed. Falls back to
        -- the stored icon name from SimdragosaDB if the API returns nil.
        local icon = C_Item.GetItemIconByID(item.itemID)
        if icon then
            row.iconTex:SetTexture(icon)
        elseif item.icon and item.icon ~= "" then
            row.iconTex:SetTexture("Interface\\Icons\\" .. item.icon)
        else
            row.iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Item name (truncated to fit column)
        local displayName = item.name or ("Item #" .. tostring(item.itemID))
        if #displayName > 22 then displayName = displayName:sub(1, 20) .. "…" end
        row.nameText:SetText(displayName)
        row.nameText:SetTextColor(0.95, 0.95, 0.95, 1)

        -- Sub-line: track label + ilvl
        local td = item.track and TRACK_DISPLAY[item.track]
        local trackName = (item.track and RW_TRACK_LABELS[item.track]) or ""
        local trackIlvl = td and td.ilvl or item.ilvl or ""
        row.subText:SetText(string.format("|cff9a8cff%s %s|r", trackName, tostring(trackIlvl)))

        -- Bar — rank-relative colour (1st=orange, 2nd=purple, 3rd=blue, 4th=green, 5th+=grey)
        local rc     = RW_RankColor(i)
        local pct    = math.max(0.02, item.dps / maxDPS)
        local fillW  = math.max(2, math.floor(RW_BAR_W * pct))
        row.barFill:SetWidth(fillW)
        row.barFill:SetColorTexture(rc[1], rc[2], rc[3], 0.85)

        -- DPS value coloured to match rank
        row.dpsText:SetText(string.format("|cff%02x%02x%02x%s|r",
            math.floor(rc[1] * 255), math.floor(rc[2] * 255), math.floor(rc[3] * 255),
            RW_FormatDPS(item.dps)))

        row:Show()
    end

    -- Hide unused pooled rows
    for i = count + 1, #rw.rows do rw.rows[i]:Hide() end

    -- Footer
    local newest = ""
    for _, item in ipairs(list) do
        if item.updated and item.updated > newest then newest = item.updated end
    end
    local whenStr = newest ~= "" and FormatStaleness(newest) or "unknown"
    rw.footer:SetText(string.format(
        "%s%d upgrade%s  ·  simmed %s%s",
        C.low, #list, #list ~= 1 and "s" or "", whenStr, C.reset
    ))
end

-- ── Cycle spec / track ────────────────────────────────────────────────────────

local function RW_CycleSpec(dir)
    if #rw.specList == 0 then return end
    rw.specIdx   = (rw.specIdx - 1 + dir + #rw.specList) % #rw.specList + 1
    rw.trackList = RW_GetTracks(rw.charKey, rw.specList[rw.specIdx])
    rw.trackIdx  = 1
    RW_Refresh()
end

local function RW_CycleTrack(dir)
    if #rw.trackList == 0 then return end
    rw.trackIdx = (rw.trackIdx - 1 + dir + #rw.trackList) % #rw.trackList + 1
    RW_Refresh()
end

local function RW_OpenSourceDropdown()
    local popup = rw.sourcePopup
    if popup:IsShown() then popup:Hide(); return end

    -- Recycle or hide old buttons
    for _, b in ipairs(rw.sourceBtns) do b:Hide() end
    rw.sourceBtns = {}

    local ROW_H   = 20
    local PAD     = 4
    local yOff    = PAD
    local popW    = popup:GetWidth()

    -- Find where __dungeons__ starts so individual dungeon entries can be indented
    local dungeonStart = math.huge
    for i, src in ipairs(rw.sourceList) do
        if src == "__dungeons__" then dungeonStart = i; break end
    end

    for idx, src in ipairs(rw.sourceList) do
        local isIndented = (idx > dungeonStart and src ~= "__dungeons__")

        local btn = CreateFrame("Button", nil, popup, "BackdropTemplate")
        btn:SetHeight(ROW_H)
        btn:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0,    -yOff)
        btn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0,    -yOff)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT",  btn, "LEFT",  isIndented and 20 or 8, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(RW_SourceDisplay(src))

        if idx == rw.sourceIdx then
            lbl:SetTextColor(1, 0.85, 0)       -- selected: gold
        else
            lbl:SetTextColor(0.88, 0.88, 0.88)
        end

        local capturedIdx = idx
        btn:SetScript("OnClick", function()
            rw.sourceIdx = capturedIdx
            -- Persist selection across sessions
            if SimdragosaConfig then
                SimdragosaConfig.lastSource = rw.sourceList[capturedIdx]
            end
            popup:Hide()
            RW_Refresh()
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground",
                              edgeFile="", tile=true, tileSize=8})
            self:SetBackdropColor(0.28, 0.22, 0.48, 0.55)
        end)
        btn:SetScript("OnLeave", function(self) self:SetBackdrop(nil) end)

        yOff = yOff + ROW_H
        table.insert(rw.sourceBtns, btn)
    end

    popup:SetHeight(yOff + PAD)
    popup:Show()
end

-- WoW spec ID → SimC spec name (must be declared before RW_Open)
local SIMC_SPEC_IDS = {
    [250]="blood",        [251]="frost",         [252]="unholy",
    [577]="havoc",        [581]="vengeance",
    [102]="balance",      [103]="feral",         [104]="guardian",     [105]="restoration",
    [1467]="devastation", [1468]="preservation", [1473]="augmentation",
    [253]="beast_mastery",[254]="marksmanship",  [255]="survival",
    [62]="arcane",        [63]="fire",            [64]="frost",
    [268]="brewmaster",   [270]="mistweaver",    [269]="windwalker",
    [65]="holy",          [66]="protection",     [70]="retribution",
    [256]="discipline",   [257]="holy",          [258]="shadow",
    [259]="assassination",[260]="outlaw",        [261]="subtlety",
    [262]="elemental",    [263]="enhancement",   [264]="restoration",
    [265]="affliction",   [266]="demonology",    [267]="destruction",
    [71]="arms",          [72]="fury",           [73]="protection",
}

-- ── Open / toggle ─────────────────────────────────────────────────────────────

local function RW_Open()
    rw.charKey    = GetCharKey()
    rw.specList   = RW_GetSpecs(rw.charKey)

    -- Default to the player's current spec
    local defaultSpecIdx = 1
    local curSpecSlot = GetSpecialization()
    if curSpecSlot then
        local curSpecId = select(1, GetSpecializationInfo(curSpecSlot))
        local curSpecName = curSpecId and SIMC_SPEC_IDS[curSpecId]
        if curSpecName then
            for i, s in ipairs(rw.specList) do
                if s == curSpecName then defaultSpecIdx = i; break end
            end
        end
    end

    rw.specIdx    = defaultSpecIdx
    rw.trackList  = RW_GetTracks(rw.charKey, rw.specList[rw.specIdx])
    rw.trackIdx   = 1
    rw.sourceList = RW_GetSources(rw.charKey)

    -- Restore last-used source filter (persisted in config)
    rw.sourceIdx = 1
    local lastSrc = SimdragosaConfig and SimdragosaConfig.lastSource
    if lastSrc then
        for i, src in ipairs(rw.sourceList) do
            if src == lastSrc then rw.sourceIdx = i; break end
        end
    end

    rw.frame:Show()
    RW_Refresh()
end

local function RW_Toggle()
    if rw.frame:IsShown() then rw.frame:Hide() else RW_Open() end
end

-- ── Frame construction (called once on ADDON_LOADED) ──────────────────────────

function RW_CreateFrame()
    local f = CreateFrame("Frame", "SimdragosaResultsFrame", UIParent, "BackdropTemplate")
    f:SetSize(RW_W, RW_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetResizable(false)
    f:RegisterForDrag("LeftButton")

    local function SavePos()
        local pt, _, rpt, x, y = f:GetPoint()
        SimdragosaConfig.windowPos = { pt, rpt, x, y }
    end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing(); SavePos() end)

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.93)
    f:SetBackdropBorderColor(0.38, 0.32, 0.65, 1)

    -- Title (dynamic — updated by RW_Refresh with char name + count)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetPoint("RIGHT",   f, "RIGHT",  -40, 0)
    title:SetJustifyH("LEFT")
    title:SetText(C.label .. "SIMDRAGOSA" .. C.reset .. "  RESULTS")
    rw.titleLabel = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Separator 1 (below title)
    local sep1 = f:CreateTexture(nil, "ARTWORK")
    sep1:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -28)
    sep1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
    sep1:SetHeight(1)
    sep1:SetColorTexture(0.38, 0.32, 0.65, 0.6)

    -- ── Spec / Track cycle rows ───────────────────────────────────────────────
    local function MakeCycleRow(yOff, prefix, cycleFn)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 14, yOff)
        lbl:SetText(C.low .. prefix .. C.reset)
        lbl:SetWidth(46)

        local prevBtn = CreateFrame("Button", nil, f)
        prevBtn:SetSize(16, 20)
        prevBtn:SetPoint("LEFT", lbl, "RIGHT", 2, 0)
        prevBtn:SetNormalFontObject("GameFontNormal")
        prevBtn:SetText(C.label .. "‹" .. C.reset)
        prevBtn:SetScript("OnClick", function() cycleFn(-1) end)

        local valLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valLbl:SetPoint("LEFT", prevBtn, "RIGHT", 3, 0)
        valLbl:SetWidth(120)
        valLbl:SetJustifyH("LEFT")
        valLbl:SetText("—")

        local nextBtn = CreateFrame("Button", nil, f)
        nextBtn:SetSize(16, 20)
        nextBtn:SetPoint("LEFT", valLbl, "RIGHT", 3, 0)
        nextBtn:SetNormalFontObject("GameFontNormal")
        nextBtn:SetText(C.label .. "›" .. C.reset)
        nextBtn:SetScript("OnClick", function() cycleFn(1) end)

        return valLbl
    end

    rw.specLabel  = MakeCycleRow(-36, "Spec:",  RW_CycleSpec)
    rw.trackLabel = MakeCycleRow(-56, "Track:", RW_CycleTrack)

    -- Source dropdown (replaces cycle row — has too many options for cycling)
    local srcRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcRowLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -76)
    srcRowLbl:SetText(C.low .. "Source:" .. C.reset)
    srcRowLbl:SetWidth(46)

    local srcToggle = CreateFrame("Button", nil, f)
    srcToggle:SetPoint("LEFT",  srcRowLbl, "RIGHT", 4, 0)
    srcToggle:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    srcToggle:SetHeight(18)

    local srcToggleBg = srcToggle:CreateTexture(nil, "BACKGROUND")
    srcToggleBg:SetAllPoints()
    srcToggleBg:SetColorTexture(0.10, 0.08, 0.18, 0.85)

    local srcBtnText = srcToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcBtnText:SetPoint("LEFT",  srcToggle, "LEFT",  6, 0)
    srcBtnText:SetPoint("RIGHT", srcToggle, "RIGHT", -14, 0)
    srcBtnText:SetJustifyH("LEFT")
    srcBtnText:SetText("All Sources")
    rw.sourceBtn = srcBtnText

    local srcArrow = srcToggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcArrow:SetPoint("RIGHT", srcToggle, "RIGHT", -4, 0)
    srcArrow:SetText(C.label .. "▾" .. C.reset)

    local srcPopup = CreateFrame("Frame", nil, f, "BackdropTemplate")
    srcPopup:SetPoint("TOPLEFT",  srcToggle, "BOTTOMLEFT",  0, -2)
    srcPopup:SetPoint("TOPRIGHT", srcToggle, "BOTTOMRIGHT", 0, -2)
    srcPopup:SetHeight(20)
    srcPopup:SetFrameStrata("TOOLTIP")
    srcPopup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 8,
        insets   = {left=2, right=2, top=2, bottom=2},
    })
    srcPopup:SetBackdropColor(0.06, 0.04, 0.14, 1.0)
    srcPopup:SetBackdropBorderColor(0.38, 0.32, 0.65, 0.8)
    srcPopup:Hide()
    rw.sourcePopup = srcPopup

    srcToggle:SetScript("OnClick", RW_OpenSourceDropdown)
    srcToggle:SetScript("OnEnter", function() srcToggleBg:SetColorTexture(0.18, 0.14, 0.30, 0.9) end)
    srcToggle:SetScript("OnLeave", function() srcToggleBg:SetColorTexture(0.10, 0.08, 0.18, 0.85) end)
    f:HookScript("OnHide", function() srcPopup:Hide() end)

    -- Separator 2 (below controls)
    local sep2 = f:CreateTexture(nil, "ARTWORK")
    sep2:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -96)
    sep2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -96)
    sep2:SetHeight(1)
    sep2:SetColorTexture(0.38, 0.32, 0.65, 0.4)

    -- Column headers
    local hdrName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrName:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -102)
    hdrName:SetText(C.low .. "UPGRADE" .. C.reset)

    local hdrDPS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrDPS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -102)
    hdrDPS:SetText(C.low .. "DPS GAIN" .. C.reset)
    rw.hdrGain = hdrDPS

    -- ── Scroll frame ─────────────────────────────────────────────────────────
    local scrollFrame = CreateFrame("ScrollFrame", "SimdragosaResultsScroll", f)
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     12,  -118)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28,   30)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(RW_W - 44)
    content:SetHeight(200)
    scrollFrame:SetScrollChild(content)
    rw.content = content

    -- Scroll bar
    local sb = CreateFrame("Slider", nil, f, "UIPanelScrollBarTemplate")
    sb:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -8, -124)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8,   34)
    sb:SetMinMaxValues(0, 1)
    sb:SetValueStep(RW_ROW_H)
    sb:SetScript("OnValueChanged", function(self, val)
        scrollFrame:SetVerticalScroll(val)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)
        sb:SetMinMaxValues(0, yRange)
        sb:SetValue(math.min(sb:GetValue(), yRange))
    end)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        sb:SetValue(sb:GetValue() - delta * RW_ROW_H * 3)
    end)

    -- ── Footer ───────────────────────────────────────────────────────────────
    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  14, 12)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 12)
    footer:SetJustifyH("LEFT")
    rw.footer = footer

    f:Hide()
    rw.frame = f

    -- Build challenge mode map name cache (covers current M+ season's dungeon IDs).
    -- C_ChallengeMode.GetMapTable returns all valid challenge map IDs for this season.
    if C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapInfo then
        for _, mapID in ipairs(C_ChallengeMode.GetMapTable()) do
            local info = C_ChallengeMode.GetMapInfo(mapID)
            if info and info.name and info.name ~= "" then
                RW_CHALLENGE_MAP_NAMES[mapID] = info.name
            end
        end
    end

    -- Debounced refresh when item data loads (icons for uncached Droptimizer items).
    -- Registered here so the closure correctly captures the local `rw`.
    local itemRefreshPending = false
    local itemEventFrame = CreateFrame("Frame")
    itemEventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemEventFrame:SetScript("OnEvent", function()
        if rw.frame:IsShown() and not itemRefreshPending then
            itemRefreshPending = true
            C_Timer.After(0.2, function()
                itemRefreshPending = false
                RW_Refresh()
            end)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------

local function RW_CreateMinimapButton()
    local angle = math.rad(220)  -- position on minimap edge
    local radius = 80            -- distance from minimap centre

    local btn = CreateFrame("Button", "SimdragosaMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetPoint("CENTER", Minimap, "CENTER",
        radius * math.cos(angle), radius * math.sin(angle))
    btn:SetClampedToScreen(true)
    btn:RegisterForDrag("LeftButton")

    -- Circular backdrop
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(32, 32)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Frost/dragon themed icon (Spell_Frost_Frozencore)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\Spell_Frost_Frozencore")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Drag to reposition along minimap edge
    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local uiScale = UIParent:GetScale()
            cx, cy = cx / uiScale, cy / uiScale
            local dx, dy = cx - mx, cy - my
            local a = math.atan2(dy, dx)
            local r = 80
            self:SetPoint("CENTER", Minimap, "CENTER",
                r * math.cos(a), r * math.sin(a))
            if SimdragosaConfig then
                SimdragosaConfig.minimapAngle = a
            end
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            -- right-click hides the button
            self:Hide()
            if SimdragosaConfig then SimdragosaConfig.minimapHidden = true end
        else
            RW_Toggle()
        end
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff9a8cffSimdragosa|r")
        GameTooltip:AddLine("Click to toggle upgrade results", 1, 1, 1)
        GameTooltip:AddLine("Right-click to hide button", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("|cff7878a0Drag to reposition|r")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    -- Restore saved position / visibility
    if SimdragosaConfig then
        if SimdragosaConfig.minimapHidden then
            btn:Hide()
        elseif SimdragosaConfig.minimapAngle then
            local a = SimdragosaConfig.minimapAngle
            btn:SetPoint("CENTER", Minimap, "CENTER",
                radius * math.cos(a), radius * math.sin(a))
        end
    end
end

-- ---------------------------------------------------------------------------
-- SimC Export  (/sdr export)
-- ---------------------------------------------------------------------------

local SIMC_SLOTS = {
    [1]  = "head",      [2]  = "neck",    [3]  = "shoulder",
    [5]  = "chest",     [6]  = "waist",   [7]  = "legs",
    [8]  = "feet",      [9]  = "wrist",   [10] = "hands",
    [11] = "finger1",   [12] = "finger2",
    [13] = "trinket1",  [14] = "trinket2",
    [15] = "back",      [16] = "main_hand", [17] = "off_hand",
}

-- raceFilename (second return of UnitRace) → SimC race name
local SIMC_RACE = {
    Human              = "human",              Orc              = "orc",
    Dwarf              = "dwarf",              NightElf         = "night_elf",
    Undead             = "undead",             Tauren           = "tauren",
    Gnome              = "gnome",              Troll            = "troll",
    BloodElf           = "blood_elf",          Draenei          = "draenei",
    Worgen             = "worgen",             Goblin           = "goblin",
    Pandaren           = "pandaren",           Nightborne       = "nightborne",
    HighmountainTauren = "highmountain_tauren", VoidElf         = "void_elf",
    LightforgedDraenei = "lightforged_draenei", DarkIronDwarf   = "dark_iron_dwarf",
    ZandalariTroll     = "zandalari_troll",    KulTiran         = "kul_tiran",
    Mechagnome         = "mechagnome",         Vulpera          = "vulpera",
    MagharOrc          = "maghar_orc",         Dracthyr         = "dracthyr",
    Earthen            = "earthen",
}

-- classFilename (second return of UnitClass) → SimC class name
local SIMC_CLASS = {
    DEATHKNIGHT = "death_knight",  DEMONHUNTER = "demon_hunter",
    DRUID       = "druid",         EVOKER      = "evoker",
    HUNTER      = "hunter",        MAGE        = "mage",
    MONK        = "monk",          PALADIN     = "paladin",
    PRIEST      = "priest",        ROGUE       = "rogue",
    SHAMAN      = "shaman",        WARLOCK     = "warlock",
    WARRIOR     = "warrior",
}

-- WoW spec ID → SimC spec name
local REGION_MAP = { [1]="us", [2]="kr", [3]="eu", [4]="tw", [5]="cn" }

-- Parse a WoW item hyperlink into a SimC item field string.
-- TWW link format (colon-delimited after "item:"):
--   1:itemID  2:enchantID  3-6:gemIDs  7:suffixID  8:uniqueID  9:level
--   10:specID  11:upgradeLevelID  12:difficultyID  13:numBonusIDs  14+:bonusIDs
--   then numModifiers, then modifier type/value pairs
local function ItemLinkToSimC(link)
    if not link then return nil end
    local itemStr = link:match("|Hitem:([^|]+)|h")
    if not itemStr then return nil end

    local f = {}
    for v in (itemStr .. ":"):gmatch("([^:]*):") do
        f[#f + 1] = tonumber(v) or 0
    end

    local id = f[1]
    if not id or id == 0 then return nil end

    local parts = { "id=" .. id }

    if (f[2] or 0) > 0 then
        parts[#parts + 1] = "enchant_id=" .. f[2]
    end

    local gems = {}
    for i = 3, 6 do
        if (f[i] or 0) > 0 then gems[#gems + 1] = f[i] end
    end
    if #gems > 0 then parts[#parts + 1] = "gem_id=" .. table.concat(gems, "/") end

    local numBonus = f[13] or 0
    if numBonus > 0 then
        local bonusIds = {}
        for i = 14, 13 + numBonus do
            if (f[i] or 0) > 0 then bonusIds[#bonusIds + 1] = f[i] end
        end
        if #bonusIds > 0 then
            parts[#parts + 1] = "bonus_id=" .. table.concat(bonusIds, "/")
        end
    end

    return table.concat(parts, ",")
end

-- Build the complete SimC profile string for the current character.
local function BuildSimCProfile()
    local name             = UnitName("player") or "unknown"
    local _, classFile     = UnitClass("player")
    local _, raceFile      = UnitRace("player")
    local level            = UnitLevel("player") or 80
    local simcClass        = SIMC_CLASS[classFile]  or classFile:lower():gsub(" ", "_")
    local simcRace         = SIMC_RACE[raceFile]    or raceFile:lower():gsub(" ", "_")
    local realm            = (GetRealmName() or "Unknown"):gsub("%s+", "")
    local regionNum        = GetCurrentRegion and GetCurrentRegion() or 1
    local region           = REGION_MAP[regionNum] or "us"

    local specIdx          = GetSpecialization() or 1
    local specId, _, _, _, role = GetSpecializationInfo(specIdx)
    local simcSpec         = SIMC_SPEC_IDS[specId] or "unknown"
    local simcRole         = (role == "HEALER") and "heal" or (role == "TANK") and "tank" or "attack"

    local talentStr = ""
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local cfgID = C_ClassTalents.GetActiveConfigID()
        if cfgID and C_ClassTalents.GetConfigExportString then
            talentStr = C_ClassTalents.GetConfigExportString(cfgID) or ""
        end
    end

    local lines = {
        "# Simdragosa Export — " .. date("%Y-%m-%d"),
        string.format('%s="%s-%s"', simcClass, name, realm),
        "level=" .. level,
        "race=" .. simcRace,
        "region=" .. region,
        "server=" .. realm:lower(),
        "role=" .. simcRole,
    }
    if talentStr ~= "" then lines[#lines + 1] = "talents=" .. talentStr end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "spec=" .. simcSpec
    lines[#lines + 1] = ""

    local slotOrder = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17 }
    for _, slotID in ipairs(slotOrder) do
        local slotName = SIMC_SLOTS[slotID]
        if slotName then
            local link     = GetInventoryItemLink("player", slotID)
            local simcItem = link and ItemLinkToSimC(link)
            if simcItem then
                lines[#lines + 1] = slotName .. "=," .. simcItem
            end
        end
    end

    return table.concat(lines, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------
-- SimulationCraft addon hook — auto-capture the official profile on /simc
-- ---------------------------------------------------------------------------

local simcHooked = false

-- Store a captured SimC profile string into SimdragosaConfig.exports.
local function SIMC_StoreProfile(profile)
    if not profile or profile == "" then return end
    -- Quick sanity check: a SimC profile always has a spec= line
    if not profile:find("\nspec=") then return end
    local charKey = GetCharKey()
    local specIdx = GetSpecialization() or 1
    local specId  = GetSpecializationInfo(specIdx)
    local spec    = SIMC_SPEC_IDS[specId] or "unknown"

    SimdragosaConfig.exports = SimdragosaConfig.exports or {}
    SimdragosaConfig.exports[charKey] = {
        simc      = profile,
        spec      = spec,
        timestamp = time(),
        enabled   = true,
    }
    print(C.label .. ADDON .. C.reset
        .. ": SimC profile captured for "
        .. C.hi .. charKey .. C.reset .. " (" .. spec .. ").")
    print("  " .. C.low .. "/reload to flush to disk — the Simdragosa app will detect it." .. C.reset)
end

-- Walk the visible frame tree rooted at obj and return the first EditBox
-- whose text looks like a SimC profile (has a spec= line).
local function SIMC_ScanForProfile(obj, depth)
    depth = depth or 0
    if depth > 6 then return nil end
    -- Some frame types (e.g. ServicesLogoutPopup) have IsShown in their metatable
    -- but crash when called, or return a tainted secure boolean — keep the test
    -- inside pcall so the tainted value never escapes to addon scope.
    local shown = false
    pcall(function() if obj:IsShown() then shown = true end end)
    if not shown then return nil end

    if obj.IsObjectType and obj:IsObjectType("EditBox") then
        local text = obj:GetText() or ""
        if text:find("\nspec=") then return text end
        return nil
    end

    if obj.GetNumChildren then
        for i = 1, obj:GetNumChildren() do
            local result = SIMC_ScanForProfile(select(i, obj:GetChildren()), depth + 1)
            if result then return result end
        end
    end

    -- Also check scroll-frame children
    if obj.GetScrollChild then
        local sc = obj:GetScrollChild()
        if sc then
            local result = SIMC_ScanForProfile(sc, depth + 1)
            if result then return result end
        end
    end

    return nil
end

-- Hook the SimC addon's slash command so every /simc auto-captures the profile.
-- Tries the slash-command table keys the SimC addon typically registers under.
function SIMC_HookFrame()
    if simcHooked then return end

    -- The SimC addon registers its slash command as SIMULATIONCRAFT (for /simc).
    -- Try a few possible keys in case future versions change it.
    local hooked = false
    for _, key in ipairs({ "SIMULATIONCRAFT", "SIMC", "SC2", "SIMULATIONCRAFT2" }) do
        if SlashCmdList[key] then
            hooksecurefunc(SlashCmdList, key, function()
                -- Give the frame one tick to populate its EditBox, then grab it.
                -- Try the known global name first; fall back to a full-tree scan.
                C_Timer.After(0.05, function()
                    local profile
                    local eb = _G["SimulationCraftEditBox"]
                    if eb then
                        local text = eb:GetText() or ""
                        if text:find("\nspec=") then profile = text end
                    end
                    if not profile then profile = SIMC_ScanForProfile(UIParent) end
                    if profile then SIMC_StoreProfile(profile) end
                end)
            end)
            hooked = true
            break
        end
    end

    if hooked then
        simcHooked = true
        print(C.label .. ADDON .. C.reset
            .. ": hooked SimulationCraft — use "
            .. C.hi .. "/simc" .. C.reset
            .. " and your profile will be captured automatically.")
    end
end

-- ---------------------------------------------------------------------------
-- DoExport  (/sdr export)
-- ---------------------------------------------------------------------------

local function DoExport()
    -- Try the known SimC addon global EditBox first (fastest, avoids frame scan crash).
    local eb = _G["SimulationCraftEditBox"]
    if eb then
        local text = eb:GetText() or ""
        if text:find("\nspec=") then
            SIMC_StoreProfile(text)
            return
        end
    end

    -- Only scan the frame tree if SimC is loaded — avoids taint errors from
    -- traversing protected frames when SimC isn't present.
    local simcLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded("SimulationCraft"))
                    or (IsAddOnLoaded and IsAddOnLoaded("SimulationCraft"))

    if simcLoaded then
        -- Fall back: scan the visible frame tree (handles renamed/future SimC versions).
        local profile = SIMC_ScanForProfile(UIParent)
        if profile then
            SIMC_StoreProfile(profile)
            return
        end
    end

    -- Nothing captured yet — if the SimC addon is loaded, open its window automatically
    -- and re-capture after a short delay so the user doesn't have to type /simc first.
    if simcLoaded then
        -- Find the SimC slash command handler (same keys we hook elsewhere).
        local simcCmd
        for _, key in ipairs({ "SIMULATIONCRAFT", "SIMC", "SC2", "SIMULATIONCRAFT2" }) do
            if SlashCmdList[key] then simcCmd = SlashCmdList[key]; break end
        end
        if simcCmd then
            print(C.label .. ADDON .. C.reset .. ": Opening SimulationCraft window…")
            simcCmd("")  -- opens /simc
            C_Timer.After(0.3, function()
                local text = ""
                local eb2 = _G["SimulationCraftEditBox"]
                if eb2 then text = eb2:GetText() or "" end
                if text == "" or not text:find("\nspec=") then
                    text = SIMC_ScanForProfile(UIParent) or ""
                end
                if text ~= "" and text:find("\nspec=") then
                    SIMC_StoreProfile(text)
                else
                    print(C.label .. ADDON .. C.reset
                        .. ": SimulationCraft window opened but no profile found yet."
                        .. " Wait for it to populate, then run /sdr export again.")
                end
            end)
            return
        end
        -- SimC loaded but no slash command found — ask user to open manually.
        print(C.label .. ADDON .. C.reset
            .. ": Type " .. C.hi .. "/simc" .. C.reset
            .. " to open the export window first, then run /sdr export.")
        return
    end

    -- SimulationCraft addon not installed — fall back to the manual builder.
    print(C.label .. ADDON .. C.reset
        .. C.low .. ": SimulationCraft addon not found — building profile manually."
        .. " Install the SimulationCraft addon for accurate exports." .. C.reset)
    local charKey = GetCharKey()
    local bProfile = BuildSimCProfile()
    local specIdx  = GetSpecialization() or 1
    local specId   = select(1, GetSpecializationInfo(specIdx))
    local spec     = SIMC_SPEC_IDS[specId] or "unknown"
    SimdragosaConfig.exports = SimdragosaConfig.exports or {}
    SimdragosaConfig.exports[charKey] = {
        simc      = bProfile,
        spec      = spec,
        timestamp = time(),
        enabled   = true,
    }
    print("  " .. C.low .. "/reload to flush to disk." .. C.reset)
end

-- Opt out the current character from auto-detection by the standalone.
local function DoExportOff()
    local charKey = GetCharKey()
    SimdragosaConfig.exports = SimdragosaConfig.exports or {}
    local existing = SimdragosaConfig.exports[charKey]
    if existing then
        existing.enabled = false
    else
        SimdragosaConfig.exports[charKey] = { enabled = false, timestamp = time() }
    end
    print(C.label .. ADDON .. C.reset .. ": auto-sim opt-out set for " .. C.hi .. charKey .. C.reset .. ".")
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_SIMDRAGOSA1 = "/simdragosa"
SLASH_SIMDRAGOSA2 = "/sdr"

SlashCmdList["SIMDRAGOSA"] = function(msg)
    local cmd = msg:lower():match("^%s*(%S+)")

    if cmd == "export" then
        local sub = msg:lower():match("^%s*%S+%s+(%S+)")
        if sub == "off" then DoExportOff() else DoExport() end

    elseif cmd == "results" or cmd == "r" then
        RW_Toggle()

    elseif cmd == "minimap" then
        local b = _G["SimdragosaMinimapButton"]
        if b then
            b:Show()
            SimdragosaConfig.minimapHidden = false
            print(C.label .. ADDON .. C.reset .. ": minimap button shown.")
        end

    elseif cmd == "toggle" then
        SimdragosaConfig.enabled = not SimdragosaConfig.enabled
        local state = SimdragosaConfig.enabled and "enabled" or "disabled"
        print(C.label .. ADDON .. C.reset .. ": tooltip lines " .. state .. ".")

    elseif cmd == "status" then
        local charKey  = GetCharKey()
        local charData = GetCharData(charKey)
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
            local match = CharKeyMatches(k, charKey) and C.green .. " ◄ you" .. C.reset or ""
            print(string.format("    %s%s%s — %d items%s", C.hi, k, C.reset, count, match))
        end

        -- Check a specific item ID if provided
        local itemArg = tonumber(msg:match("%d+"))
        if itemArg then
            local charData = GetCharData(charKey)
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
                        if sd.champion then parts[#parts+1] = string.format("champ=%.1f",  sd.champion) end
                        if sd.heroic   then parts[#parts+1] = string.format("heroic=%.1f", sd.heroic)   end
                        if sd.mythic   then parts[#parts+1] = string.format("mythic=%.1f", sd.mythic)   end
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
        print("  /simc                  — open SimulationCraft export (auto-captured by Simdragosa)")
        print("  /sdr export            — capture from open /simc window (or manual fallback); /reload to flush")
        print("  /sdr export off        — opt this character out of auto-sim detection")
        print("  /sdr results           — open/close the upgrade results window")
        print("  /sdr minimap           — show the minimap button if hidden")
        print("  /sdr toggle            — show/hide tooltip lines")
        print("  /sdr status            — show stored item count for your character")
        print("  /sdr staleness <n>     — hide sims older than N days (0 = never)")
        print("  /sdr debug             — show DB contents and character key")
        print("  /sdr debug <itemID>    — check if a specific item ID has sim data")
    end
end

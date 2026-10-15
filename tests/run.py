"""Offline test harness for Simdragosa.lua.

Runs the addon under Lua 5.1 (WoW's dialect) with a stubbed WoW API, so the
pure logic and the UI code paths can be exercised without the game:

    pip install lupa
    python tests/run.py

Frames are inert stubs: this checks the code runs and produces the right
text, not how it looks in game.
"""

from __future__ import annotations

import sys
from pathlib import Path

import lupa.lua51 as lupa51

ROOT = Path(__file__).resolve().parent.parent

STUBS = r"""
local calls = { prints = {}, texts = {} }
_G.__calls = calls

local function obj(kind)
  local o = { __kind = kind, __scripts = {}, __events = {}, __shown = true, __w = 520, __h = 540, __text = nil }
  -- Unknown methods are no-ops; fields the addon stores on frames
  -- (SimdragosaBadge, itemID, ...) must read as nil like on a real frame.
  return setmetatable(o, { __index = function(t, k)
    if type(k) ~= "string" or k:match("^Simdragosa") or not k:match("^%u") then return nil end
    return function(self, ...) return nil end
  end })
end

local frames = {}
_G.__frames = frames

local function frameMethods(f)
  f.SetScript = function(self, name, fn) self.__scripts[name] = fn end
  f.GetScript = function(self, name) return self.__scripts[name] end
  f.HookScript = function(self, name, fn)
    local prev = self.__scripts[name]
    self.__scripts[name] = function(...) if prev then prev(...) end fn(...) end
  end
  f.RegisterEvent = function(self, ev) self.__events[ev] = true end
  f.Show = function(self) self.__shown = true; local s = self.__scripts.OnShow; if s then s(self) end end
  f.Hide = function(self) self.__shown = false; local s = self.__scripts.OnHide; if s then s(self) end end
  f.IsShown = function(self) return self.__shown end
  f.GetWidth = function(self) return self.__w end
  f.GetHeight = function(self) return self.__h end
  f.SetSize = function(self, w, h) self.__w, self.__h = w, h end
  f.SetWidth = function(self, w) self.__w = w end
  f.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
  f.SetText = function(self, t) self.__text = t; calls.texts[#calls.texts+1] = t end
  f.GetText = function(self) return self.__text end
  f.CreateTexture = function() local t = obj("Texture"); frameMethods(t); return t end
  f.CreateFontString = function() local t = obj("FontString"); frameMethods(t); return t end
  return f
end

function CreateFrame(kind, name, parent, template)
  local f = frameMethods(obj(kind))
  f.__shown = (kind ~= "Frame" or name == nil) and true or true
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end

UIParent = CreateFrame("Frame")
Minimap = CreateFrame("Frame")
GameTooltip = CreateFrame("GameTooltip")
GameTooltip_Hide = function() end

function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end calls.prints[#calls.prints+1] = table.concat(t, " ") end

-- player
__player = { name = "Xian", realm = "Silver Moon", specSlot = 1, specId = 63, lootSpec = 0, equipped = {}, bags = {} }
function UnitName() return __player.name end
function GetRealmName() return __player.realm end
function UnitLevel() return 90 end
function GetSpecialization() return __player.specSlot end
function GetSpecializationInfo(slot) return __player.specId, "Fire", "", 0, "DAMAGER" end
function GetLootSpecialization() return __player.lootSpec end
function GetInventoryItemID(_, slot) local e = __player.equipped[slot]; return e and e.id end
function GetInventoryItemLink(_, slot) local e = __player.equipped[slot]; return e and ("link:" .. e.id .. ":" .. e.ilvl) end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
function IsShiftKeyDown() return false end
function GetItemInfo() return nil end
function GetLootRollItemLink(id) return __rolls and __rolls[id] end

C_Item = {
  GetDetailedItemLevelInfo = function(x)
    if type(x) == "string" then local il = x:match(":(%d+)$"); return tonumber(il) end
    return 300, false, 300
  end,
  GetItemCount = function(id) return __player.bags[id] or 0 end,
  GetItemInfoInstant = function(link) return tonumber(link:match("^link:(%d+)")) end,
  GetItemIconByID = function() return 12345 end,
}
C_Timer = { After = function(_, fn) fn() end }
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Map = {}
EJ_GetInstanceInfo = function() return nil end
EJ_GetDifficulty = function() return __ejDiff or 15 end
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) _G.__tooltipFn = fn end }
SlashCmdList = {}
ChatEdit_InsertLink = function() end
hooksecurefunc = function() end
time = os.time
date = os.date
"""


def load(lua, db_src: str):
    lua.execute(STUBS)
    lua.execute(db_src)
    src = (ROOT / "Simdragosa.lua").read_text(encoding="utf-8")
    chunk = lua.eval("function(s) local f, e = loadstring(s, 'Simdragosa.lua'); if not f then error(e) end; return f end")(src)
    ns = lua.table()
    chunk("Simdragosa", ns)
    # Fire ADDON_LOADED for us on every frame that registered for it.
    lua.execute("""
      for _, f in ipairs(__frames) do
        if f.__events.ADDON_LOADED and f.__scripts.OnEvent then f.__scripts.OnEvent(f, "ADDON_LOADED", "Simdragosa") end
      end
    """)
    return ns


TODAY = __import__("datetime").date.today()
OLD = (TODAY - __import__("datetime").timedelta(days=60)).isoformat()

DB = f"""
SimdragosaDB = {{
  ["Xian-SilverMoon"] = {{
    [1] = {{ specs = {{ {{ spec="fire", heroic=4210, mythic=6900 }}, {{ spec="frost", heroic=2800 }} }},
             ilvl=334, name="Voidbound Signet", source="Kith'ix", sourceType="raid", updated="{TODAY}" }},
    [2] = {{ specs = {{ {{ spec="fire", heroic=900 }} }}, ilvl=334, name="Old Ring", source="Boss B",
             sourceType="raid", updated="{OLD}" }},
    [3] = {{ specs = {{ {{ spec="fire", heroic=1500, mythic=1800 }} }}, ilvl=334, name="Dungeon Cloak",
             source="Murder Row", sourceType="dungeon", updated="{TODAY}" }},
    [4] = {{ specs = {{ {{ spec="fire", crafted=2500 }} }}, ilvl=331, name="Crafted Bracers",
             source="Epic Profession Items", sourceType="crafted", stats="crit/mastery", updated="{TODAY}" }},
    [5] = {{ specs = {{ {{ spec="fire", heroic=700 }} }}, ilvl=334, name="Dungeon Boots",
             source="Murder Row", sourceType="dungeon", updated="{TODAY}" }},
  }},
  ["Brakka-SilverMoon"] = {{
    [1] = {{ specs = {{ {{ spec="arms", heroic=3300 }} }}, ilvl=334, name="Voidbound Signet", updated="{TODAY}" }},
  }},
}}
"""

failures: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  -- {detail}"))
    if not cond:
        failures.append(name)


def tooltip_lines(lua, ns, item_id: int) -> list[str]:
    lines = lua.execute("""
      local fn, id = ...
      local out = {}
      local tt = { AddLine = function(_, l) out[#out+1] = l end }
      fn(tt, { id = id })
      return out
    """, ns.test.Tooltip_OnItem, item_id)
    return [lines[i] for i in range(1, len(lines) + 1)]


def strip(s: str) -> str:
    import re
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", s)


def main() -> int:
    lua = lupa51.LuaRuntime(unpack_returned_tuples=True)
    ns = load(lua, DB)
    t = ns.test

    # ── gains ──
    g, track, spec = t.BestGain(lua.eval("SimdragosaDB['Xian-SilverMoon'][1]"), "fire")
    check("BestGain picks the best track for the spec", (g, track) == (6900, "mythic"), f"{g} {track}")
    g, track = t.GainForIlvl(lua.eval("SimdragosaDB['Xian-SilverMoon'][1]"), "fire", 321)
    check("GainForIlvl maps a 321 drop to the Hero track", (g, track) == (4210, "heroic"), f"{g} {track}")
    g, track = t.GainForIlvl(lua.eval("SimdragosaDB['Xian-SilverMoon'][4]"), "fire", 331)
    check("GainForIlvl uses the stored ilvl for crafted", (g, track) == (2500, "crafted"), f"{g} {track}")

    # ── tooltip ──
    lines = [strip(l) for l in tooltip_lines(lua, ns, 1)]
    joined = "\n".join(lines)
    spec_lines = [l for l in lines if l.startswith("[")]
    check("tooltip lists the current spec first", spec_lines and spec_lines[0].startswith("[fire]"), joined)
    check("tooltip shows both tracks", "+4.2k DPS (Heroic)" in joined and "+6.9k DPS (Mythic)" in joined, joined)
    check("tooltip shows the drop source", "Drops from: Kith'ix" in joined, joined)
    check("tooltip lists alts that gain from the item", "Alts: Brakka +3.3k" in joined, joined)

    raw = tooltip_lines(lua, ns, 1)
    other = [l for l in raw if strip(l).startswith("[frost]")]
    check("other specs are greyed", other and other[0].startswith("|cff7878a0[frost]"), str(other))

    lines = "\n".join(strip(l) for l in tooltip_lines(lua, ns, 2))
    check("stale sims are dimmed, not hidden", "(stale — re-sim)" in lines and "+900 DPS" in lines, lines)

    lua.execute("SimdragosaConfig.hideStale = true")
    check("hideStale hides stale sims", tooltip_lines(lua, ns, 2) == [], "")
    lua.execute("SimdragosaConfig.hideStale = false")

    lines = "\n".join(strip(l) for l in tooltip_lines(lua, ns, 4))
    check("crafted gain shows the stat pair", "(Crafted · crit/mastery)" in lines, lines)

    lua.execute("__player.equipped[11] = { id = 1, ilvl = 321 }")
    lines = "\n".join(strip(l) for l in tooltip_lines(lua, ns, 1))
    check("equipped copy is called out", "Equipped at ilvl 321" in lines, lines)
    check("a track at or below the worn ilvl is marked", "Heroic, have 321" in lines, lines)
    check("a higher track still counts", "(Mythic)" in lines, lines)
    lua.execute("__player.equipped[11] = nil; __player.bags[3] = 1")
    lines = "\n".join(strip(l) for l in tooltip_lines(lua, ns, 3))
    check("owned-in-bags is called out", "You already own one" in lines, lines)
    lua.execute("__player.bags[3] = nil")

    lua.execute("__player.lootSpec = 64")
    lines = "\n".join(strip(l) for l in tooltip_lines(lua, ns, 1))
    check("loot spec is labelled", "[frost · loot]" in lines, lines)
    lua.execute("__player.lootSpec = 0")

    check("unknown items add nothing", tooltip_lines(lua, ns, 999) == [], "")

    # ── source summary ──
    rows = t.RW_SourceSummary("Xian-SilverMoon", "fire", None, "dungeon")
    check("dungeon summary groups by source", len(rows) == 1 and rows[1].name == "Murder Row"
          and rows[1].count == 2 and rows[1].total == 2500, "")
    rows = t.RW_SourceSummary("Xian-SilverMoon", "fire", None, None)
    names = [rows[i].name for i in range(1, len(rows) + 1)]
    check("full summary is ranked by total gain", names[0] == "Kith'ix", str(names))

    # ── slash commands and results window run cleanly ──
    def slash(msg: str) -> list[str]:
        lua.execute("__calls.prints = {}")
        lua.eval("SlashCmdList.SIMDRAGOSA")(msg)
        p = lua.eval("__calls.prints")
        return [strip(p[i]) for i in range(1, len(p) + 1)]

    out = slash("keys")
    check("/sdr keys ranks dungeons", any("Murder Row" in l for l in out), str(out))
    out = slash("bosses")
    check("/sdr bosses ranks raid bosses", any("Kith'ix" in l for l in out), str(out))
    out = slash("")
    check("/sdr help lists the new commands", any("/sdr keys" in l for l in out) and any("/sdr vault" in l for l in out), "")
    slash("results")
    check("results window opens", lua.eval("SimdragosaResultsFrame:IsShown()"), "")
    def texts() -> list[str]:
        t = lua.eval("__calls.texts")
        return [strip(str(t[i])) for i in range(1, len(t) + 1)]

    check("items view lists item names", "Voidbound Signet" in texts(), "")
    lua.execute("__calls.texts = {}; SimdragosaConfig.rwMode = 'sources'")
    lua.execute("SimdragosaResultsFrame.__scripts.OnSizeChanged(SimdragosaResultsFrame)")
    tx = texts()
    check("sources view renders one row per source", "Kith'ix" in tx and any("sources" in x for x in tx), str(tx[:12]))
    lua.execute("SimdragosaConfig.rwMode = 'items'; SimdragosaConfig.rwSort = 'source'")
    lua.execute("SimdragosaResultsFrame.__scripts.OnSizeChanged(SimdragosaResultsFrame)")
    out = slash("staleness hide")
    check("/sdr staleness hide", lua.eval("SimdragosaConfig.hideStale") is True, str(out))
    slash("staleness dim")
    out = slash("loot")
    check("/sdr loot toggles alerts", lua.eval("SimdragosaConfig.lootAlerts") is False, str(out))
    slash("loot")

    # ── loot alerts ──
    def fire_loot(*args) -> list[str]:
        lua.execute("__calls.prints = {}")
        lua.execute("""
          local args = {...}
          for _, f in ipairs(__frames) do
            if f.__events[args[1]] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, unpack(args)) end
          end
        """, *args)
        p = lua.eval("__calls.prints")
        return [strip(p[i]) for i in range(1, len(p) + 1)]

    out = fire_loot("ENCOUNTER_LOOT_RECEIVED", 1, 1, "link:1:321", 1, "Xian-SilverMoon", "MAGE")
    check("own loot upgrade is announced", any("you got link:1:321" in l and "+4.2k" in l for l in out), str(out))
    out = fire_loot("ENCOUNTER_LOOT_RECEIVED", 1, 1, "link:1:334", 1, "Brakka-SilverMoon", "WARRIOR")
    check("someone else's upgrade-for-you is announced", any("Brakka looted" in l and "+6.9k" in l for l in out), str(out))
    out = fire_loot("ENCOUNTER_LOOT_RECEIVED", 1, 999, "link:999:334", 1, "Xian", "MAGE")
    check("non-upgrades stay quiet", out == [], str(out))
    lua.execute("__rolls = { [7] = 'link:3:321' }")
    out = fire_loot("START_LOOT_ROLL", 7)
    check("loot rolls are announced", any("roll on link:3:321" in l for l in out), str(out))

    # ── Great Vault ──
    lua.execute("""
      C_WeeklyRewards = {
        GetActivities = function() return {
          { rewards = { { itemDBID = "a" }, { itemDBID = "b" } } },
          { rewards = { { itemDBID = "c" } } },
        } end,
        GetItemHyperlink = function(id) return ({ a = "link:1:334", b = "link:999:334", c = "link:3:334" })[id] end,
      }
      WeeklyRewardsFrame = CreateFrame("Frame")
    """)
    fire_loot("ADDON_LOADED", "Blizzard_WeeklyRewards")
    lua.execute("__calls.prints = {}; WeeklyRewardsFrame:Show()")
    p = lua.eval("__calls.prints")
    out = [strip(p[i]) for i in range(1, len(p) + 1)]
    check("vault opening lists upgrade choices, best first",
          len(out) >= 3 and "Great Vault upgrades" in out[0] and "link:1:334" in out[1] and "link:3:334" in out[2]
          and not any("link:999" in l for l in out), str(out))

    # ── Encounter Journal badges ──
    lua.execute("""
      local sb = {}
      EncounterJournal = { encounter = { info = { LootContainer = { ScrollBox = sb } } } }
      ScrollUtil = { AddInitializedFrameCallback = function(box, cb) __ejCallback = cb end }
      __ejDiff = 16
    """)
    fire_loot("ADDON_LOADED", "Blizzard_EncounterJournal")
    badge = lua.execute("""
      local row = CreateFrame("Button"); row.itemID = 1
      __ejCallback(nil, row, {})
      local miss = CreateFrame("Button"); miss.itemID = 999
      __ejCallback(nil, miss, {})
      return row.SimdragosaBadge and row.SimdragosaBadge:GetText(), miss.SimdragosaBadge
    """)
    check("journal loot rows get a gain badge for the shown difficulty",
          badge[0] is not None and strip(badge[0]) == "+6.9k" and badge[1] is None, str(badge))

    print()
    print(f"{len(failures)} failure(s)" if failures else "all passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

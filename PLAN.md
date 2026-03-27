# Simdragosa Addon — Development Plan

## Overview

A World of Warcraft retail addon that reads DPS gain data produced by the
[Simdragosa](https://github.com/Xiantus/auto-sim) sim tool and injects it
directly into item tooltips in-game.

**Goal:** When you hover over any item that has been simmed, the tooltip shows
"+2.3k DPS (Heroic)" without leaving the game.

---

## Architecture

```
Simdragosa (web app)
    └─ runs Droptimizer sims
    └─ parses Raidbots report JSON
    └─ writes Simdragosa.lua → WoW SavedVariables folder
               │
               ▼
WoW loads Simdragosa.lua on login / /reload
               │
               ▼
SimdragosaDB["CharName-Realm"][itemID] = { heroic=N, mythic=N, ... }
               │
               ▼
Addon hooks TooltipDataProcessor
    └─ reads itemID from tooltip data
    └─ looks up current character's entry in SimdragosaDB
    └─ appends DPS gain line(s) to tooltip
```

### Data Contract

The Lua SavedVariables file written by auto-sim uses this structure:

```lua
SimdragosaDB = {
  ["CharName-RealmName"] = {
    [itemID] = {
      heroic  = 2341.7,   -- DPS gain in Heroic (may be absent)
      mythic  = 3102.0,   -- DPS gain in Mythic (may be absent)
      ilvl    = 639,      -- item level simmed at
      name    = "Item Name",
      updated = "2026-03-27",
    },
  },
}
```

---

## Phase 1 — Core (MVP) ✅ in progress

**Goal:** Show DPS gains in tooltips. Nothing else.

- [x] `Simdragosa.toc` — addon manifest, declares `SavedVariables: SimdragosaDB`
- [x] `Simdragosa.lua` — tooltip hook, DB lookup, line formatting
- [x] Multi-difficulty display (Heroic + Mythic on separate lines)
- [x] Colour coding: green (high gain) / yellow (medium) / grey (low)
- [x] Staleness indicator: "Simmed: 3 days ago" in subdued colour
- [x] Graceful no-op when `SimdragosaDB` is missing or entry not found

**Deliverable:** Drop the `Simdragosa/` folder into `Interface/AddOns/`, do
`/reload`, and tooltips show gains immediately.

---

## Phase 2 — Quality & Robustness

**Goal:** Make it feel polished and handle edge cases.

- [ ] `/simdragosa` slash command — print current character's sim summary to chat
- [ ] Config option: toggle tooltip lines on/off (`/simdragosa toggle`)
- [ ] Config option: hide entries older than N days (`/simdragosa staleness 14`)
- [ ] Show "⚠ outdated" indicator if data is older than the configured threshold
- [ ] Handle realm name normalisation (spaces → no-spaces, connected realms)
- [ ] `SavedVariables: SimdragosaDB, SimdragosaConfig` — persist user preferences

---

## Phase 3 — Multi-spec Awareness

**Goal:** Show the right data per spec.

- Currently all gains are stored per character, not per spec. If a user sims
  both Fire and Frost they get the same tooltip.
- Extend the data contract to include `spec` in the key or as a sub-key.
- Show spec label next to the DPS value when multiple specs are stored.

Depends on auto-sim exporting spec-tagged data (auto-sim change needed).

---

## Phase 4 — In-Game Import (stretch goal)

**Goal:** Import data without touching the filesystem at all.

- Add a `/simdragosa import <base64-string>` command.
- Auto-sim generates a compact base64-encoded payload via `/api/tooltip-export?format=import`.
- User pastes the string in-game; addon decodes and merges into `SimdragosaDB`.

This removes the need for file system access entirely — good for users on
managed hosting or Linux/Mac where the SavedVariables path is awkward.

---

## File Structure

```
simdragosa-addon/           ← git repo root
├── CLAUDE.md               ← branching rules
├── PLAN.md                 ← this file
├── .gitignore
└── Simdragosa/             ← drop this folder into Interface/AddOns/
    ├── Simdragosa.toc      ← addon manifest
    └── Simdragosa.lua      ← all addon logic
```

---

## Installation

1. Copy the `Simdragosa/` folder to:
   `World of Warcraft/_retail_/Interface/AddOns/Simdragosa/`
2. Run sims in Simdragosa (auto-sim).
3. Either:
   - **Auto:** configure `wow_savedvars_path` in auto-sim Settings — Lua is
     written automatically after each sim.
   - **Manual:** Settings → Download `Simdragosa.lua` → place in
     `WTF/Account/<ACCOUNT>/SavedVariables/`
4. Log in or `/reload` in WoW.
5. Hover over a simmed item — tooltip shows DPS gain.

---

## WoW API Notes

- **Tooltip hook:** `TooltipDataProcessor.AddTooltipPostCall` (retail 10.0+)
- **Item ID:** available as `data.id` in the callback
- **Character key:** `UnitName("player") .. "-" .. GetRealmName():gsub(" ", "")`
- **No networking:** WoW addons cannot make HTTP requests — all data must
  arrive via SavedVariables or in-game import strings.
- **Interface version:** target `110107` (The War Within Season 2, patch 11.1.7)

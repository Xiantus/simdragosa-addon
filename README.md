# Simdragosa Addon

WoW addon companion for [Simdragosa](https://github.com/Xiantus/simdragosa-standalone) — a Windows desktop app that automates Droptimizer sims on Raidbots.

![Version](https://img.shields.io/github/v/release/Xiantus/simdragosa-addon) ![WoW](https://img.shields.io/badge/WoW-Retail-blue)

---

## What it does

**Tooltip DPS gains** — after running sims in the desktop app, hover any item in your bags, the dungeon journal, or a loot tooltip to see its DPS upgrade value:

```
[Frost]  +1.2k DPS (Heroic)  +1.5k DPS (Mythic)
[Fire · loot]  +900 DPS (Heroic)
Drops from: Kith'ix
Alts: Brakka +3.3k
Simdragosa — simmed 2 days ago
```

Your current spec is listed first; other specs are greyed and your loot spec is labelled. Tracks you already wear at that item level or higher are greyed ("have 321"), and items you already own are called out. Old sims are dimmed rather than hidden. For warbound or BoE gear, the **Alts** line shows which of your other characters gains most.

No logout needed — type `/reload` after the desktop app finishes a sim and the new data is live.

**Results window** — `/sdr results` or the minimap button. Resizable. Lists upgrades for your spec and track with the boss or dungeon each drops from; **View: Sources** ranks bosses and dungeons by the total upgrade value they hold. Click a source to see its items.

**Loot & vault alerts** — a chat line when you loot an upgrade, when someone else loots one you'd want (so you can ask for a trade), when a roll comes up on one, and a ranked list of your Great Vault choices when you open the vault.

**Encounter Journal badges** — loot rows in the dungeon journal show your gain for the difficulty you're viewing.

**Which key / boss** — `/sdr keys` ranks dungeons and `/sdr bosses` ranks raid bosses by how much upgrade value they hold for your spec.

**SimC export helper** — type `/sdr export` in-game and the addon opens the SimulationCraft window, captures your full profile (gear, talents, stats), and stores it in your SavedVariables. The desktop app detects the new export automatically and pre-fills your character's SimC string — no copy-pasting required.

---

## Requirements

- The [Simdragosa desktop app](https://github.com/Xiantus/simdragosa-standalone/releases) — this addon only displays data that the app generates. Install the app first.
- The [SimulationCraft addon](https://www.curseforge.com/wow/addons/simulationcraft) — required for `/sdr export` to capture accurate profiles. Without it, a basic fallback profile is used (missing talents).

---

## Installation

Install from [CurseForge](https://www.curseforge.com/wow/addons/simdragosa) via the CurseForge app, or download the latest zip from [Releases](https://github.com/Xiantus/simdragosa-addon/releases) and unzip it into your `Interface\AddOns\` folder.

---

## Quick start

1. Install the [Simdragosa desktop app](https://github.com/Xiantus/simdragosa-standalone/releases) and complete its setup
2. Install this addon and the [SimulationCraft addon](https://www.curseforge.com/wow/addons/simulationcraft)
3. Log into the character you want to sim
4. Type `/sdr export` — the addon captures your current profile and the desktop app picks it up within seconds
5. In the desktop app, select your character and loot tracks, then click **GO**
6. When the sim finishes, type `/reload` in WoW — DPS gains now appear on item tooltips

---

## Slash commands

| Command | Description |
|---------|-------------|
| `/sdr export` | Capture your SimC profile from the SimulationCraft addon and sync it to the desktop app |
| `/sdr export off` | Opt this character out of auto-detection by the desktop app |
| `/sdr toggle` | Show or hide DPS gain lines on tooltips |
| `/sdr results` | Open the in-game results window |
| `/sdr status` | Show how many items have sim data loaded for your character |
| `/sdr keys` | Rank dungeons by upgrade value for your spec |
| `/sdr bosses` | Rank raid bosses by upgrade value for your spec |
| `/sdr vault` | List Great Vault choices that are upgrades |
| `/sdr loot` | Turn loot / roll / vault upgrade alerts on or off |
| `/sdr alts` | Show or hide the alt-gains line on tooltips |
| `/sdr staleness <days>` | Sims older than N days count as stale (0 = never) |
| `/sdr staleness hide\|dim` | Hide stale sims, or dim them (default) |
| `/sdr debug` | Show your character key and all stored sim data |
| `/sdr debug <itemID>` | Check sim data for a specific item ID |

---

## Development

`python tests/run.py` runs the addon under Lua 5.1 with a stubbed WoW API (needs `pip install lupa`). It checks the logic and that every UI path runs; it cannot show how anything looks in game.

---

## Troubleshooting

**Tooltips show no data after `/reload`**
Run `/sdr debug` — it prints the character key the addon is looking for (e.g. `Xiage-TarrenMill`). Make sure the name and realm in the desktop app match exactly, including capitalisation.

**`/sdr export` says "SimulationCraft addon not found"**
Install the [SimulationCraft addon](https://www.curseforge.com/wow/addons/simulationcraft). Without it, the export falls back to a basic profile that may not be accepted by Raidbots.

**The desktop app isn't picking up my export**
Make sure the **WoW Retail Folder** is configured in the desktop app's Settings — it watches the addon's `SavedVariables` file for new exports.

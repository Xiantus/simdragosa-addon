# Git Branching Workflow

## Branch Strategy

- **`master`** — production/release branch. Only receives merges from `develop`.
- **`develop`** — integration branch for local testing. All feature and fix branches merge here first.
- **Feature/fix branches** — branch off `develop`, merge back into `develop` when done.

## Development workflow

The git repo at `C:\Users\Xiant\Documents\Projects\simdragosa-addon` is junction-linked
to `C:\Games\World of Warcraft\_retail_\Interface\AddOns\Simdragosa`.
**Editing the repo immediately updates the live in-game addon** — `/reload` in WoW is enough to test.

1. Never commit directly to `master`.
2. Make changes on `develop`. User can `/reload` in WoW to test immediately — no release needed.
3. **Do NOT release until the user explicitly says so.** Wait for confirmation before releasing to CurseForge.

## Release process (on user go-ahead only)

```
# On develop — bump TOC version first
# Edit Simdragosa.toc: ## Version: X.Y.Z
git add Simdragosa.toc
git commit -m "release: vX.Y.Z"
git checkout master
git merge develop
git push
# Tag AFTER pushing — must use git push for the tag, not gh release create
# (gh release create uses the API and does not fire a push event → workflow never runs)
git tag vX.Y.Z
git push origin vX.Y.Z
gh release create vX.Y.Z --title "vX.Y.Z" --notes "..."
```

---

# Project Context (Wiki)

At session start, read these wiki pages for full project context:

- `C:\Users\Xiant\Documents\Projects\vault\Big Vault\wiki\sources\project-simdragosa-addon.md` — phase status, data contract, key constraints
- `C:\Users\Xiant\Documents\Projects\vault\Big Vault\wiki\concepts\wow-addon.md` — WoW addon architecture patterns
- `C:\Users\Xiant\Documents\Projects\vault\Big Vault\wiki\overviews\simdragosa-ecosystem.md` — how the addon fits with standalone and auto_sim

## Key facts (summary)

- WoW Lua addon: reads `SimdragosaData.lua` (written by standalone/auto_sim) and injects DPS gain lines into item tooltips
- **WoW addons cannot make HTTP requests** — all data arrives via SavedVariables file written by the desktop app
- Hooks `TooltipDataProcessor.AddTooltipPostCall` (retail 10.0+)
- Available on CurseForge; released via GitHub Actions workflow
- Phase 2 mostly done; Phase 3 (multi-spec) requires coordinated change in `simdragosa-standalone`/`auto_sim` to tag exported data by spec

## Data contract (`SimdragosaData.lua`)

```lua
SimdragosaDB = {
  ["CharName-RealmName"] = {
    [itemID] = { heroic = 2341.7, mythic = 3102.0, ilvl = 639, name = "Item Name", updated = "2026-03-27" },
  },
}
```

# currentDate
Today's date is 2026-03-27.

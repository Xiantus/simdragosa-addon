# Git Branching Workflow

## Branch Strategy

- **`master`** — production/release branch. Only receives merges from `develop`.
- **`develop`** — integration branch for local testing. All feature and fix branches merge here first.
- **Feature/fix branches** — branch off `develop`, merge back into `develop` when done.

## Rules

1. Never commit directly to `master`.
2. Create feature/fix branches from `develop`:
   ```
   git checkout develop
   git checkout -b feature/my-feature
   ```
3. Merge completed work into `develop` first:
   ```
   git checkout develop
   git merge feature/my-feature
   ```
4. To release, bump `## Version:` in `Simdragosa.toc`, merge `develop` into `master`, then push:
   ```
   # On develop — bump TOC version first
   # Edit Simdragosa.toc: ## Version: X.Y.Z
   git add Simdragosa.toc
   git commit -m "release: vX.Y.Z"
   git checkout master
   git merge develop
   git push
   ```

## Versioning rules

- **Never pre-bump the TOC version.** The `## Version:` in `Simdragosa.toc` must only be set in the release commit, not ahead of time.
- **TOC version must match the git tag** that triggers the CurseForge release workflow. A CI check enforces this — the workflow fails if they diverge.
- The BigWigs packager reads the TOC version, not the tag name. A mismatch means CurseForge publishes the wrong version number.

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

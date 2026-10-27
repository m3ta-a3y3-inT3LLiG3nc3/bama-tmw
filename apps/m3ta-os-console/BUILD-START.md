# Build start — M3ta-OS Console

## Spun-up project

Spun up 2026-10-27 from `specs/m3ta-os-console.md` (fork commit `453fdc9`)
so the Mac build lane can start immediately. This folder is the BAMA
`new-mac-app` template scaffold plus the app-brief spec copies:

- `docs/BRIEF.md` — the spec's Brief block
- `docs/STORIES.md` — the spec's Stories block
- `docs/SPEC.md` — the full spec (How it works + Gotchas live here)
- `Fixtures/mesh-state-2026-10-26.json` — the seed MeshState fixture
  (copy of `specs/fixtures/mesh-state-2026-10-26.json`)
- Template scaffold with AppName `M3taOSConsole`, bundle id
  `com.th3m3taway.m3taosconsole`, placeholders filled, scripts executable

AppName note: `M3taOSConsole` is the mechanical UpperCamelCase form of the
working title "M3ta-OS Console". The product name is M3ta's call (spec);
if he picks another name, rename before the first release.

Two deliberate deviations from running `new-app.sh` on the Mac:

1. **No `git init` in this folder.** The app lives in the `bama-tmw` fork
   repo under `apps/`; the fork's commits carry it. Do not run
   `new-app.sh` again — the scaffold is done.
2. **The template's `Item` model was NOT renamed.** See Mac step 3.

## Mac lane — first steps, in order

1. **Sync.** Pull the fork (Copilot worktrees at
   `~/copilot-worktrees/bama-tmw/`), then `cd apps/m3ta-os-console`.
   BAMA skills must be installed on the Mac
   (`npx skills@latest add daveebbelaar/bama -y --agent '*' --skill '*'`).
2. **Toolchain check** (new-mac-app step 1):
   `swift --version` (6.2 or later) and `sw_vers -productVersion`
   (26.0 or later). On macOS 15, set `.macOS(.v15)` in `Package.swift`
   and `LSMinimumSystemVersion` to 15 in `Info.plist.in`, and skip
   Liquid Glass APIs.
3. **First code step — replace the template model, do not rename it.**
   The console does not map onto the template's single SwiftData list
   (merge doc §3.4 + `docs/SPEC.md`, How it works):
   - `MeshState` is a **Codable snapshot loaded from local JSON**, not a
     SwiftData model. Seed it from `Fixtures/mesh-state-2026-10-26.json`.
   - `TaskEnvelope` is the stored record (SwiftData or local JSON).
   - Replace `SidebarItem`'s cases with the spec's surfaces: Pluto
     Status, Pairing, Mesh. Replace the template item list with the
     status page skeleton from S-001.
   Then `./build.sh --open` — prove the toolchain before feature code.
4. **Design pass** (router order, right after the scaffold):
   `mac-design` + `design-system` from the first view — native, system
   accent — and `app-icon` so every snapshot carries the real icon.
   Status colors must not overclaim: untested reads as untested
   (spec, Gotchas).
5. **improve-loop, M1 only**, in dependency order: S-001 → S-002 →
   S-003 → S-006, one story per commit. Pairing acceptance steps are
   **manual** (M3ta at the Mac, Ruth Local install + permission grants)
   and are recorded in the story — never faked by a snapshot. Stop at
   M1: M2 dispatch (S-004, S-005) starts on M3ta's go at the M1 check-in.
6. **Checks the template ships with:**
   `swift test --scratch-path ~/Library/Developer/M3taOSConsole/test-build`,
   `tools/selftest.sh`, `tools/snap.sh` (light + dark, every page).

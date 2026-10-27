# Build start — M3taTasks

## Spun-up project

Spun up 2026-10-27 from `specs/m3ta-tasks.md` (fork commit `fb90107`)
so the Mac build lane can start immediately. This folder is the BAMA
`new-mac-app` template scaffold plus the app-brief spec copies:

- `docs/BRIEF.md` — the spec's Brief block
- `docs/STORIES.md` — the spec's Stories block
- `docs/SPEC.md` — the full spec (How it works + Gotchas live here)
- `docs/SCREEN-INDEX.md` — the captured Todoist screen index
  (2026-10-26 browser walk; the clone reference in written form)
- `docs/screens/` — where the reference PNGs go, in the stories'
  `Screens:` order. `docs/screens/*.png` is gitignored on purpose:
  the capture ran on M3ta's real account and the shots hold real task
  titles (spec, Gotchas). Until PNGs land, the stories' `Screens:`
  lines still say "pending capture" — reconcile them against
  `docs/SCREEN-INDEX.md` when the files exist.
- Template scaffold with AppName `M3taTasks`, bundle id
  `com.th3m3taway.m3tatasks`, placeholders filled, scripts executable

Already done here (new-mac-app step 6, as the spec and the build brief
prescribe — the Mac lane does NOT repeat it):

- `Item` → `Task` everywhere, with the spec's fields (`isCompleted`,
  `completedAt`, `dueDate`, `sortOrder` — optional/defaulted, so M2/M3
  add UI, not schema surgery). `ItemTitle` → `TaskTitle`, "New Item" →
  "New Task", `addItem` → `addTask`.
- `Project` type defined in the model (name, colorName, sortOrder,
  isArchived) and registered in the container; its UI is M2 (S-008+).
- `SidebarItem` pages are Inbox / Today / Completed (symbols tray,
  calendar, checkmark.circle). Page **filtering** is not in the
  scaffold — it lands with S-001/S-004/S-006 via `TaskQueries`.
- Seed data is titles only (the user-stories seed rule).

One deliberate deviation from running `new-app.sh` on the Mac:
**no `git init` in this folder.** The app lives in the `bama-tmw` fork
repo under `apps/`; the fork's commits carry it. Do not run
`new-app.sh` again — the scaffold is done.

Open items only M3ta closes: the app name (working title M3taTasks),
and the M1 → M2 go at the M1 check-in.

## Mac lane — first steps, in order

1. **Sync.** Pull the fork (Copilot worktrees at
   `~/copilot-worktrees/bama-tmw/`), then `cd apps/m3ta-tasks`.
   BAMA skills must be installed on the Mac
   (`npx skills@latest add daveebbelaar/bama -y --agent '*' --skill '*'`).
2. **Toolchain check** (new-mac-app step 1):
   `swift --version` (6.2 or later) and `sw_vers -productVersion`
   (26.0 or later). On macOS 15, set `.macOS(.v15)` in `Package.swift`
   and `LSMinimumSystemVersion` to 15 in `Info.plist.in`, and skip
   Liquid Glass APIs.
3. **First build.** `./build.sh --open` — the template builds and runs
   as is; this proves the toolchain before any feature code.
4. **Design pass** (router order, right after the scaffold):
   `mac-design` + `design-system` from the first view — native, system
   accent, Apple's own controls; not Todoist's look (spec, Brief) —
   and `app-icon` so every snapshot carries the real icon.
5. **improve-loop, M1 only** (S-001 → S-007). Every M1 story carries
   "UX: pending": run `ux-design` for the story first (it also starts
   `docs/GLOSSARY.md`), then code per `swift-swiftui` + `mac-design`,
   build, snapshot with seed data (`APP_SEED=1`, pages limited to the
   story's), compare against `docs/SCREEN-INDEX.md` — structure and
   behavior, native controls win — fix, commit with the story marked
   `done` in the same commit. M1's stories share one skeleton, so M1
   may land as one commit per the loop's exception; from M2 on,
   strictly one story per commit. Never point the loop at M3ta's real
   Todoist data — seed and snapshot data only.
6. **M1 check-in, then stop.** Run `improve-architecture` (act only on
   a `Strong` top recommendation), then `build-and-verify`: full
   light-and-dark snapshot set plus `swift test
   --scratch-path ~/Library/Developer/M3taTasks/test-build`,
   `tools/selftest.sh`, `tools/snap.sh`. Report stories done/blocked
   and finish with `./build.sh --open`. M2/M3 stories are written but
   parked; starting them needs M3ta's go.

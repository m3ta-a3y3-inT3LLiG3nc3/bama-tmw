# Dashboard build notes, 2026-11-02

Build of the M3ta Way dashboard from docs/designs/m3ta-way-dashboard-2026-11-02.md
plus its navigation and features addenda, on branch
agent/k0ad33/bama-console-m2, VM clone only. Nothing was pushed.

## Nothing was compiled

This VM has no Swift toolchain (checked /usr/bin, /usr/local/bin, /opt,
swiftly). All code below is written and reviewed, not built. Every test
is specified, not executed. The suite run, packaging, visual checks,
and live acceptance are Mac-side steps, listed in the run sheet at the
end. Until the Mac run passes, the dashboard is unverified, not done
(parent spec, Definition of done 6).

## Defaults used (the four resolve questions)

1. Tokens: system 1, the updated Th3 M3ta Way brand kit (gold #C9A227
   on deep black #0A0A0C / #121214, accent #E6C65C), with the spec's
   labeled token-completion step done in DashboardTokens.swift. Cosmic
   Lightbody tokens do not appear on the dashboard.
2. Launch default: Dashboard is the home screen (Command group above
   Home, QB tab first). CONSOLE_SCREEN still overrides for scripted
   launches.
3. DashboardState producer: a snapshot producer on the existing QB
   check-in cadence. The shared composition step is code
   (DashboardSnapshotComposer in ConsoleCore); the capture job and the
   file writing stay QB-side, and the only values composed in are the
   spec's allowed loopback probe set.
4. Speech: designed only. No microphone or speech code this round; the
   orb maps to real run states and the copy says speech is not wired.

## Deviations (one line each)

- Panel accent edge uses the system-1 brand gold, not the kente gold the parent spec's Frames paragraph names: one gold on the dashboard.
- Schema: the addenda's tab fields (comms, modules, Intelligence projects, platform rows, census, app rows) reuse SurfaceRow in five optional arrays instead of new per-tab types: one row shape, one renderer.
- DashboardStore: a set-but-unreadable override path shows the error and never substitutes the bundled fixture (the spec's deliberate deviation from BotStore, kept).
- The bundled fixture carries no JARVIS surface row: the view renders JARVIS live from probes, and the composer writes the row into producer-captured files.
- The dashboard renders the dark system-1 palette in both appearances: the brand kit defines no light variant, and none was invented.
- Social panel in the fixture is absent (nil), so the panel renders its designed state with the TikTok and Postiz blockers named: no producer read exists yet, and no metric was invented to fill it.
- Only six M3ta-OS modules are named in the addendum record; the module grid renders those six and waits for the producer to name the rest.

## What is code, what is scaffold

Code (desktop, apps/m3ta-os-console):
- ConsoleCore: DashboardState + addendum contracts, loader, brief
  ranking, staleness, Panel 4 ordering, DashboardSnapshotComposer,
  DashboardTokens + DashboardStatus (stage 1, 0bbbf30).
- Tests: DashboardStateTests (14) + DashboardThemeTests (2); the suite
  is now 70 specified tests, the existing 54 untouched (stage 2,
  5ae6075).
- App: DashboardStore, Dashboard screen with the seven panels, tab bar
  (QB / Hermes / Meta OS / A.D.A.M.), ticker with Reduce Motion static
  replacement, ChatRunStore lift, RootView gating change, Settings
  field, Brain search carry-over, brand asset bundled via package.sh
  (stage 3, c7aee5d).

Scaffold (iOS, stage 4, 0560fc2):
- Real target, real shared core: M3taOSConsoleMobile builds against
  ConsoleCore and renders the same bundled snapshot (glance +
  approvals pattern). Remaining step is Xcode-side packaging on the
  Mac: bundle identifier, signing, app icons, and a producer-sync path
  for fresher snapshots. SPM alone does not produce a shippable iOS
  app bundle.

Not in this build:
- Web app: no new web code. The dashboard's web surface remains the
  existing M3ta Way Dashboard artifact and Digital HQ; this spec family
  covers the Console. A hosted web build of the dashboard is a separate
  change with its own surface decision.
- The egm-goldfish agent registration (Mac-side, M3ta's session), the
  JARVIS approvals list endpoint, the Skills Brain registry, and the
  snapshot producer job itself (QB-side scheduling) are all named
  dependencies, untouched here. CopilotKit Intelligence project
  m3ta-os-console (15527) is referenced in the fixture only; nothing
  was reconfigured.

## Mac run sheet

Run on the Mac, in the bama-tmw checkout, after pulling this branch:

1. Suite: `cd apps/m3ta-os-console && swift test` — expect 70 tests,
   0 failures. Failures in DashboardStateTests or DashboardThemeTests
   are this build's; the 54 pre-existing tests must pass unchanged.
2. Build: `swift build` (debug) must complete for all three products,
   including M3taOSConsoleMobile for the iOS platform
   (`swift build --triple arm64-apple-ios26.0` or open in Xcode and
   build the mobile scheme once, to validate the manifest).
3. Package: `zsh scripts/package.sh` — produces dist/M3taOSConsole.app.
4. Asset check (acceptance test 11): the packaged app contains
   Contents/Resources/brand/th3-m3ta-way-badge-circle-1080px.png and it
   byte-matches ~/workspace/m3ta-g3ar/brand-kit/th3-m3ta-way/png/th3-m3ta-way-badge-circle-1080px.png
   (`cmp` the two files); the hero shows the badge, not the drawn
   placeholder.
5. Visual checks (spec tests 7-10): sidebar shows Command > Dashboard
   first and launch lands on it; CONSOLE_SCREEN=Overview still lands on
   Overview and every pre-existing screen is unchanged; with JARVIS
   running, approvals count, JARVIS row, REA skills, and brain status
   show live values with checked-at times; with JARVIS stopped, the
   offline states render and snapshot panels still render; Reduce
   Motion on: no stagger, orb static, ticker a static block; VoiceOver
   reads each panel header as name + capsules + source line.
6. Live acceptance (spec test 12): the packaged app opens on the
   dashboard end to end. Expected weak panels, recorded in advance:
   Panels 4 and 7 (snapshot content is only as good as the hand-made
   fixture) and the social panel (designed state until the first
   producer run).
7. EGM equivalents (tests 14-15 of the EGM runtime step): unchanged by
   this build and still owed from that spec: register egm-goldfish in
   the packaged Meta OS app (M3ta's session), run the two-review
   statelessness check, and one real review run. The dashboard does
   not depend on any of it; its EGM row stays blocked until then.

## Correction note, 2026-11-02 (logo mark)

M3ta flagged that a logo mark he was shown read as "two Ms side by side."
That reading is wrong for this brand. The only correct mark is the
ratified brand-kit master: ONE single continuous wave-line M inside a
gold ring (master SVG:
`th3-m3ta-way/svg/th3-m3ta-way-badge-circle.svg`, viewBox 240, ring r108
stroke 12 in #C9A227, one wave path, round caps and joins).

What this build bundled before this note, verified 2026-11-02:

- `apps/m3ta-os-console/Resources/brand/th3-m3ta-way-badge-circle-1080px.png`
  byte-matches the brand kit's own 1080px export
  (md5 a6fc30521df6fd2de71f9f95835eb536 on both copies). A visual read of
  the PNG confirms the single wave-line M in the gold ring. Faithful.
- `apps/m3ta-os-console/Resources/brand/th3-m3ta-way-badge-circle.svg`
  is byte-identical to the master SVG (diff clean). Faithful.
- The drawn fallback in `BrandBadgeImage` (a system cube glyph on a
  rounded rectangle) renders only when the bundled asset is missing,
  for example dev runs via `swift run`. It is a placeholder, never the
  mark, and its accessibility label says so.

Added by this correction:

- `apps/m3ta-os-console/Resources/brand/th3-m3ta-way-badge-circle-3d-1600px.png`,
  a byte-exact copy of the brand kit's 3D gold medallion render
  (md5 7e5ad06170e3220ca4cfa3c3aa7b17c9 on both copies; kit file dated
  2026-10-31, the newest badge render on record). Visual read confirms
  the same single wave-line M, extruded in brushed gold inside the gold
  ring on black.
- Intended use: hero medallion presentation. Neither the dashboard
  spec, its addenda, nor the current code defines a medallion slot; the
  hero (`DashboardView.heroPanel`) uses `BrandBadgeImage` with the flat
  1080px badge at the spec's asset path, unchanged. The medallion ships
  bundled and ready; wiring it into the hero needs a spec slot first,
  so no UI changed in this correction.
- Packaging: `scripts/package.sh` copies the whole `Resources/brand`
  directory into the app (`cp -R Resources/brand`), so the medallion
  reaches the packaged app with no script change. Add it to the Mac
  run sheet asset check above: the packaged app should also contain
  `Contents/Resources/brand/th3-m3ta-way-badge-circle-3d-1600px.png`,
  byte-matching the brand-kit file (`cmp`).

Rule, standing: never redraw, redesign, or approximate the mark. Only
the brand-kit masters and their own renders ship. Any surface that
needs the logo takes a byte-exact copy from
`~/workspace/m3ta-g3ar/brand-kit/th3-m3ta-way/` and verifies it with a
checksum or `cmp` before it is called done.

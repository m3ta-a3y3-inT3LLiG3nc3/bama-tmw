# CRM module build notes — 2026-11-06

Spec: `specs/m3ta-os-console-crm.md` (stories CRM-001..CRM-006).
Order: M3ta, 2026-11-06 — build the CRM into the BAMA native Console
(the registration stub's shell slot; stub updated in the same pass,
see below).

## Defaults and deviations

- Deviation from the registration stub, recorded in the spec header:
  the stub registered a `web-app-wrapper` shell for a standalone
  `m3ta-crm` app. The build is a native module (a fifth dashboard
  tab) inside the M3ta-OS Console instead, talking to the CRM's
  machine API directly. No web view anywhere in the module.
- Token route: `CRM_API_TOKEN` from the app's launch environment
  only. The Console stores no CRM credential; Settings carries only
  the base-URL override. Packaged-app injection is the run sheet's
  `open --env` step (a Finder launch inherits no shell environment).
- Security default added at the EGM gate: the token is full-scope on
  the server, so the client treats a plain-http non-loopback base
  URL as unbound and never sends it there.

## EGM gate

Elephant draft: `specs/m3ta-os-console-crm.md` (full context: CRM
integration contract, manifest, route handlers, service layer).
Goldfish pass: one fresh zero-context subagent, draft + referenced
sources only. 23 findings: 8 blockers, 10 should-fix, 5 notes.
All resolved in the spec and, where they touched code, in the build:

- Blockers: per-field nullability stated + null fixtures (F1); POST
  answers are bare rows at 200, models decode them via optional
  includes (F2); per-route contact include variants + tags ignored
  (F3); snapshot membership named as exactly five reads, contacts
  on-demand only (F4); read triggers fixed to on-show/manual/
  post-write, no dashboard probe-loop membership (F5); token
  full-scope + loopback/HTTPS-only sending, enforced in CRMConfig
  (F6); packaged-app token injection route named (F7); failure
  handling defined for non-JSON 500s and 401/503 without assumed
  bodies (F8).
- Should-fix, all applied: summary field types + displayed totals
  (F9); id is identity, slug is the cross-system key only (F10);
  search cap 25 + fullName order documented (F11); retention `days`
  omitted client-side, server default wins (F12); header policy per
  method + acceptance reads the resolved agent id (F13); config
  precedence one rule + trailing-slash normalisation + test (F14);
  server-sends-full/client-decodes-subset wording + no payload or
  header logging rule (F15); confirm disables in flight, duplicates
  possible and stated (F16); kind is a fixed picker over the
  server's values (F17); fixture provenance stated, live-capture
  step added to the run sheet (F18); server due filter authoritative,
  client parser display-only (F19).
- Notes, recorded as accepted limits in the spec: no pagination,
  non-atomic snapshot, checkedAt = refresh completion (F20);
  wording aligned to due-or-overdue, empty states per panel (F21);
  stub deviation recorded (F22); model fields verified against the
  Prisma schema the routes serialize (F23).

## What is code, what is scaffold

Code (desktop, apps/m3ta-os-console):

- ConsoleCore: `CRMClient.swift` — CRMConfig (env-first resolution,
  bindProblem), CRMDate (fractional-second parser), the payload
  models (summary, company with `_count`, contact, task, retention),
  the client (five reads, contacts search, two HITL writes, loadAll).
  `CRMState.swift` — CRMSnapshot (five Probes, nil-never-zero count
  helpers) + CRMStore (observable, in core so iOS shares it).
- Tests: `CRMClientTests.swift` — 19 tests: config/unbound (incl.
  insecure-base and trailing-slash), decode pins for every read
  shape (nulls, `_count`, nested rows, assignee subset), write body
  builders, server error text, bare-row POST decode, snapshot/store.
  The pre-existing 70 specified tests are untouched.
- App: `CRMTabView.swift` — fifth dashboard tab ("CRM") with
  Pipeline, Roster, Follow-ups due, Retention alerts, Open tasks,
  and the Add forms; unbound and offline faces distinct from live.
  Wiring: DashboardTab case + switch (DashboardView.swift), Settings
  base-URL field + token note (App.swift). Dashboard design system
  throughout (system 1 tokens, DashboardPanel).
- Specs index: `specs/README.md` row added.

Not in this build:

- iOS companion CRM screen: ConsoleCore is shared, so the store and
  client are ready; no mobile view was written (spec: not in this
  milestone).
- Company snapshots, inbound Orbit sync, deals/notes/bookings/email
  surfaces from the tab (spec: dropped for this milestone).

CRM repo, same pass:

- `docs/bama/m3ta-crm.bama.md`: status flipped from stub to built
  (native-module kind, file map, auth note). The manifest and
  INTEGRATIONS.md were inputs and are unchanged.

## Verification state (honest)

- **Not compiled, not run.** This VM has no Swift toolchain (`swift`
  not found on PATH or in the standard install roots, checked
  2026-11-06), and SwiftUI/macOS compilation is Mac-side regardless.
  No claim is made that the module builds or runs until the run
  sheet below is executed on the Mac.
- Code was written against the repo's existing patterns (JarvisClient
  Probe/decode seams, DashboardStore discipline, DashboardTabs panel
  shapes, Swift Testing fixtures) and the CRM's actual route/service
  code, not its docs alone.
- Unit fixtures are authored from the route handlers + service layer
  (provenance stated in the spec); they are not live captures yet.

## Mac run sheet

Run on the Mac, in the bama-tmw checkout, after pulling this commit.
The CRM server must be running on the same machine for the live
steps (`cd ~/workspace/repos/nova-ai-crm`, its `.env` carrying
CRM_API_TOKEN, `npm run start` or the usual dev command; it answers
on localhost:3120).

1. Suite: `cd apps/m3ta-os-console && swift test` — expect 89 tests
   (70 pre-existing + 19 CRM), 0 failures. Failures in
   CRMClientTests are this build's; the 70 must pass unchanged.
2. Build: `swift build` (debug) for all three products.
3. Package: `zsh scripts/package.sh` — produces dist/M3taOSConsole.app.
4. Unbound check (CRM-001): launch the packaged app with NO token in
   its environment (plain Finder launch). The CRM tab shows the
   unbound screen naming CRM_API_TOKEN. No roster content renders.
5. Live check (CRM-002..004): relaunch with the token injected:
   `open --env CRM_API_TOKEN=<the server's token> dist/M3taOSConsole.app`
   (if `open --env` is unavailable on this macOS, run the binary
   directly with the variable set in the shell:
   `CRM_API_TOKEN=... dist/M3taOSConsole.app/Contents/MacOS/M3taOSConsole`).
   Open the CRM tab: roster matches the web dashboard's companies,
   summary totals match, follow-ups/retention/tasks render with
   checked-at times. Stop the CRM server: the tab's offline face
   shows per-read reasons, never an empty roster.
6. Write check (CRM-005/006): create "Test Person" from the Add
   form; find the contact in the web app and confirm the ActivityLog
   attributes the write to the resolved agent id (default
   m3ta-os-console). Create a task with kind follow_up and a past
   due date; it appears in the tab's follow-ups and the web app.
   Delete both test rows in the web app afterwards.
7. Fixture capture (EGM F18): with the server running, capture
   sanitised live responses for summary, companies, contacts (with
   and without q), followups, retention, tasks, and one POST of each
   kind (tokens and personal data scrubbed), and diff the shapes
   against Tests/ConsoleCoreTests/CRMClientTests.swift fixtures.
   Any field mismatch is a model fix in ConsoleCore, not a fixture
   edit alone.
8. Visual checks: CRM tab sits fifth in the tab bar (QB, Hermes,
   Meta OS, A.D.A.M., CRM); panels use the system-1 palette in both
   appearances; Reduce Motion and VoiceOver behavior matches the
   other tabs (panel headers read as name + capsules + source line).

# The M3ta Way dashboard for the M3ta-OS Console

Status: Elephant draft, 2026-11-02. For Goldfish review, then M3ta's
resolve step. Nothing in this spec is built yet unless a section says so.
Scope: one new screen in the M3ta-OS Console app (this repo,
apps/m3ta-os-console), plus the snapshot data it renders. No new runtime,
no new server, no Mac-side work in the MVP.

## Objective

Give M3ta one Jarvis-style command surface inside the Console he already
has: a Today hero brief, a voice presence, the approvals queue, the state
of his command surfaces, the revenue engine, the Skills Brain, and the
knowledge brain, each panel labeled with where its data comes from and
whether that feed is live, designed, or blocked. The dashboard is a
reading and routing surface. Execution stays where it already lives:
JARVIS executes, the Jev gate holds consequential actions, Otto is the
Mac harness and launcher, Orbit is the cloud record.

## Terms

| Term | Meaning in this spec |
| --- | --- |
| Panel | One bounded region of the dashboard screen, with one job, one data source, and one status. |
| Snapshot | A JSON state file captured by a producer outside the Console, loaded by the app the way `MeshState` and `BotMap` load today: a path override in Settings, else a bundled copy. |
| Status vocabulary | `live` (a feed the Console reads now), `snapshot` (rendered from a snapshot file, age shown), `designed` (specced here, no feed and no code yet), `blocked` (a named decision or endpoint is missing). Every panel carries exactly one of these, on screen. |
| Action levels | L0 observe, L1 prepare/draft, L2 reversible internal execution, L3 explicit approval (sends, publishes, purchases, deploys, deletions), L4 never without direct instruction (money movement, signatures, secrets, security overrides). Per the action-card skill. The dashboard itself performs L0 only in the MVP. |
| Hero | The top frame of the Today screen: brand badge, greeting line, the day's brief, and the voice presence. One hero per screen, per the theme rule in tokens.json. |

## Current state (scoped to its evidence)

Checked in this repo, 2026-11-02:

- Screens today (`App.swift`): Overview, Pluto status, Pairing, Pairing
  result, Mesh, Bots, Brain, Copilot. There is no dashboard or Today
  screen. Overview is a status-card grid over a snapshot plus two
  read-only loopback checks, and it is the closest existing relative of
  this design.
- Live reads that exist in ConsoleCore: JARVIS health, model route, and
  REA skills via `JarvisClient` (127.0.0.1:9782 and :9783, read-only
  GETs); Copilot health via `CopilotHealth`; brain status and search via
  `BrainClient` (rea-mcp tools `rea_brains_status`, `rea_brains_search`).
  The rea-mcp health payload carries a `pending` count (pending
  approvals), visible in `JarvisLiveView`. No approvals list endpoint is
  called anywhere in the app today.
- Chat exists: `CopilotPanel` sends AG-UI runs to the single JARVIS
  runtime's default agent route and folds streamed events into messages.
  Text only. There is no speech input, no speech output, and no avatar
  anywhere in the app.
- Snapshot pattern exists: `Store` loads `MeshState` from a Settings
  path or the bundled fixture and shows source plus age (`AgeBanner`,
  suppressed on Overview today). `BotStore` does the same for `BotMap`.
  Both fixtures are dated (mesh-state-2026-10-26, bot-map-20261027), so
  anything rendered from them is old until a producer refreshes them.
- The EGM runtime step (docs/designs/egm-runtime-step-2026-11-02.md) is
  built in ConsoleCore (`EGMReview.swift`) on the VM side. Its JARVIS
  agent, `egm-goldfish`, is not registered on the Mac yet, so the step
  is not live. This spec does not depend on it.
- Brand, and a conflict this spec does not hide: three token systems
  are on record. (1) The dashboard brief from M3ta, 2026-11-02: gold
  #C9A227 on black #0a0a0c / #121214, accent #e6c65c, matching the
  Digital HQ surface and the ratified Th3 M3ta Way badge (brand-kit
  spec, ~/workspace/m3ta-g3ar/brand-kit/spec.md: the badge stays
  unchanged). (2) The in-repo theme, Resources/theme/tokens.json,
  "TMW Cosmic Lightbody v1", marked CONFIRMED direction 2026-10-27:
  onyx #0E0A12, cosmic red #F0505A, violet #B48CF2, no gold primary.
  (3) `Theme.swift` house tokens traced to the disk brand kits: navy
  #001635, gold #C58E33. The app today renders system (2), with gold
  present only as a kente accent under a 15 percent cap. Which system
  governs the dashboard is M3ta's call at the resolve step; the Design
  section below is written so either choice drops in as tokens, not as
  a redesign.
- Patterns adopted from the Matt Wolfe Control Center analysis
  (~/workspace/your_files/wolfe-pair-integration-2026-11-02.md, section
  3): A3 daily-brief-as-snapshot, A1 strict-mention evidence rule, A5
  deterministic-first ranking with local models first-class. A2 and A4
  are out of scope here (knowledge front end, client builds).
- Revenue facts allowed on screen, and their sources: the offer ladder
  as ruled by M3ta (Snapshot $333.33, Assessment $5,555.55, Company
  Brain $11,111.11, AaaS $1,111.11/mo); public selling gated on WS-06
  copy approval plus live Stripe (Stripe is test-mode today); verified
  empire revenue is $0 (empire audit, 2026-11-01). No other revenue
  number exists to display. There is no commission ledger yet (gap G7
  in the revenue engine template), so no per-offer or per-channel money
  breakdown exists to chart.
- Skills Brain: a spec exists, its Phase 1 is blocked on M3ta's
  registry-of-record ruling. The REA skills list JARVIS exposes
  (/api/rea/skills, tools exposed count in `JarvisLiveView`) is a
  different thing from the Skills Brain registry and must not be
  presented as it.
- Knowledge brain: the Console Knowledge module is specced in
  specs/m3ta-os-console-knowledge.md (uncommitted in this working tree)
  and not built. The Notion hub is built; the vault mirror job and the
  OpenKnowledge corpus import are not running, and the corpus import is
  the named structural gap. `BrainView` search over rea-mcp works
  against the vault today.

## Definition of done

1. A Dashboard screen ships in the Console with the seven panels in the
   Design section, each showing its status word and its source line on
   screen, in the app's existing snapshot-age style.
2. Opening the dashboard triggers no external collection: no mail, web,
   tracker, or cloud calls. It renders the loaded snapshot immediately.
   The only network traffic allowed on open is the loopback read set
   the Console already performs (JARVIS health, models, REA skills,
   brain status), each labeled with its checked-at time.
3. No number appears on any panel unless it traces to a named source
   named on that panel. Unknown renders as "Unknown", never as zero,
   following the app's existing rule ("Never guessed; unknown stays
   unknown").
4. Every animation honors Reduce Motion: with it on, the dashboard is
   fully usable and fully informative with all motion replaced by
   instant state changes.
5. New unit tests pass with the existing suite on the Mac, including
   contrast tests for every text-bearing color pair the dashboard
   introduces, in the pattern of `ThemeTests`.
6. Live verification on the Mac: the packaged app opens on the
   dashboard, every live-labeled panel shows data from the running
   JARVIS, and every snapshot panel shows its capture time. Until that
   passes, the dashboard is marked unverified, not done.

## Design

### Shell and layout

- One new screen, `Dashboard`, added to the sidebar under a new group
  "Command" placed above "Home", and made the default selection on
  launch (today Overview is the default). Existing screens do not move
  or change behavior. `CONSOLE_SCREEN` keeps working; a new value,
  "Dashboard", selects the new screen for scripted launches.
- Layout, top to bottom, one scrolling column at the app's current
  minimum window (960x640) and wider:
  1. Hero frame (Panel 1 fused with Panel 2's presence orb).
  2. Approvals strip (Panel 3), full width, directly under the hero,
     because it is the one panel that asks M3ta to act.
  3. A two-column grid below: Command surfaces (Panel 4) and Revenue
     engine (Panel 5) side by side, then Skills Brain (Panel 6) and
     Knowledge brain (Panel 7) side by side. Below the app's current
     adaptive-grid minimum the columns stack, in the same order.
- Frames: panels reuse the existing card language (the `StatusCard`
  tile: 14pt radius, glass effect, 150pt min height is Overview's;
  dashboard panels are variable height and do not inherit the fixed
  height). Each panel has a header row: panel name, status word as a
  capsule in the `StatusTag` style, and a source line in caption size.
  No panel hides its source line in a tooltip or a detail view.
- Navigation out: panels route, they do not duplicate. Tapping a panel
  header's link control selects the existing screen that owns the
  detail (Copilot, Brain, Bots, Mesh) or opens the external surface
  (Otto, Orbit, Paperclip, Plane, Linear) in the browser. Link controls
  are real controls with labels, not whole-card click targets, so
  VoiceOver and keyboard users get the same routes.

### Panel 1: Today / hero brief

- Job: the day at a glance, Wolfe pattern A3. The brief is a ranking of
  what is already saved, never a collection run.
- Content, deterministic-first (pattern A5): (a) date and greeting
  line; (b) up to five brief lines, ranked by a fixed rule order:
  approvals waiting first, then calendar items inside 24 hours, then
  blocked or stale items from the snapshot, then one knowledge line
  (queue state), then one revenue line (gate state, not money). Each
  line carries its source tag. If a source is absent from the snapshot,
  its slot is omitted, not filled.
- Data source: `DashboardState` snapshot (below). Calendar content
  enters only through the snapshot; the Console gains no calendar
  access of its own in the MVP.
- Status: `snapshot`. The hero shows "Brief as of <capturedAt>" in the
  AgeBanner style. Note the existing exception: `AgeBanner` is
  suppressed on Overview today; the dashboard does not inherit that
  suppression, it always shows age.
- Ranking is code, not a model call. A model-written summary line is a
  Later item and, when it lands, it ranks below the deterministic
  lines and is labeled as model-written with its route (local first).

### Panel 2: Voice (Hermes presence)

- Job: the speaking presence M3ta asked for, scoped to what is true.
- What exists today: text chat with the JARVIS runtime (Copilot
  screen), streaming, with a working state already visible ("JARVIS is
  working..." while a run streams). Hermes as the voice layer is the
  architecture's named owner of voice, and no Hermes voice surface is
  wired into the Console or JARVIS today: no speech recognition, no
  speech synthesis, no wake word, no avatar feed exists in this repo.
- MVP design: a presence orb in the hero. Its states map one to one to
  real run states from the existing accumulator: idle, listening is
  NOT a state (there is no microphone), working (a chat run is
  streaming), speaking is NOT a state (there is no speech output),
  offline (runtime unreachable). The orb animates only in `working`,
  driven by arriving stream events, so the motion is evidence, not
  decoration. Beside the orb, one line states the truth in words:
  "Voice: text chat live. Speech in and out: designed, not wired."
  A button routes to the Copilot screen.
- Designed, not in MVP: microphone input, spoken replies, and an
  animated speaking avatar. Each needs its own spec and its own
  decisions (speech engine local vs cloud, where audio is processed,
  what leaves the machine). This spec does not pick them.
- Status: `designed` for speech; the orb and its working state are
  `live` once built, fed by the chat run state.

### Panel 3: Approvals queue (Jev-gated)

- Job: everything waiting on M3ta's decision, in one strip, with the
  Jev pre-screen result attached before he is asked.
- What exists today: the rea-mcp health payload exposes a pending
  approvals count, already rendered in `JarvisLiveView`. The Jev gate
  itself (pre-screen: safe-to-present, routing, confidence; Jev
  advises, M3ta resolves) lives on the JARVIS side. No endpoint that
  lists the queue items is called by the Console today, and this spec
  does not invent one.
- MVP design: the strip shows the live pending count from the same
  health probe the app already makes, labeled `live`, source
  "rea-mcp /health, pending". Below the count, the queue list area
  shows its real state: `blocked`, with the blocker named on screen:
  "Queue detail needs a JARVIS endpoint that lists pending items; the
  health probe exposes the count only."
- Later, gated on that endpoint existing: queue rows (title, action
  level L0-L4 as a chip, Jev routing and confidence, source system),
  and decision controls. A decision is an L3 action: it presents the
  action card (objective, target, exact payload, impact, risk) and
  fires only on M3ta's explicit approval of that card. The dashboard
  never batches approvals and never pre-approves. Denied cards are
  final and are logged as denied.
- Status: count `live`, list `blocked`.

### Panel 4: Command surfaces

- Job: one row per surface M3ta commands from, with its state and a
  route to it: Otto, Orbit, Paperclip, Plane, Linear, plus JARVIS
  itself.
- Rows and truth:
  - JARVIS: `live`. Health, default model route, paid-model count from
    the probes the app already makes (the Models card data).
  - Orbit: `snapshot`. The Console has no Orbit feed. Bot-map counts
    (Orbit agents at map time) exist in `BotMap`; anything fresher
    needs a snapshot producer. Known operational facts that belong in
    the snapshot, with dates, not as live claims: quota state, plan
    renewal. The panel shows the snapshot's words and date, nothing
    fresher-looking.
  - Otto: `blocked` for control, `snapshot` for presence. Otto control
    waits on M3ta's in-app scoped grant; the Console has no Otto feed
    at all. The row says so and routes out; it does not show a status
    it cannot know. Whether Otto is running is knowable on the Mac but
    not by this app today, so it renders "Unknown".
  - Paperclip: `snapshot`. Per-box boards are snapshots by design, not
    sync. The row shows board identity and snapshot age from
    `DashboardState`; no counts the snapshot does not carry.
  - Plane: `snapshot`. Delivery layer; project and issue counts only
    as of the snapshot that carries them, with its date.
  - Linear: `snapshot`. Same rule.
- Deterministic-first ranking (pattern A5): rows sort blocked first,
  then stale (snapshot older than 24 hours), then live. No model
  touches this list.
- Strict-mention rule (pattern A1) applies to any future feed: a
  surface is only shown in a state that a direct read of that surface
  established. A snippet, a chat claim, or another panel's data never
  promotes a row's status.

### Panel 5: Revenue engine

- Job: the state of the money system, with only confirmed numbers.
- Content: the offer ladder as four rows (Snapshot $333.33, Assessment
  $5,555.55, Company Brain $11,111.11, AaaS $1,111.11/mo), each marked
  with its gate state: public selling gated on WS-06 copy approval and
  live Stripe; both gates shown as closed today, in words, with the
  Stripe leg labeled "test mode". One summary line: "Verified revenue
  to date: $0 (empire audit, 2026-11-01)." That line carries its date
  permanently; a fresher number replaces it only from a named source.
- What the panel never does in the MVP: no charts, no per-offer totals,
  no channel attribution, no projections. The commission ledger that
  would feed them (gap G7) does not exist, so the panel shows a
  `blocked` sub-row naming it: "Commission ledger: not built (G7).
  Per-offer money appears here when it exists."
- Data source: the ladder and gate states are confirmed terms, carried
  as constants in `DashboardState` with a `confirmedAt` date, not read
  from any live system. Status: `snapshot` for the panel, `blocked`
  for the ledger sub-row.
- Any future action from this panel (sending an offer, opening a
  checkout) is L3 or L4 and routes through the action card. The panel
  itself sells nothing.

### Panel 6: Skills Brain

- Job: the state of the skills registry, kept visibly separate from
  the REA tool list.
- Content, two blocks that never merge:
  1. REA skills (from JARVIS): `live`. Tools exposed count and the
     first names, from /api/rea/skills, the same data `JarvisLiveView`
     renders. Labeled "JARVIS REA skills, not the Skills Brain
     registry."
  2. Skills Brain registry: `blocked`. One line, the blocker in words:
     "Phase 1 waits on the registry-of-record ruling." Below it, what
     the registry will hold when it exists (skill name, owner surface,
     version, where it is wired), as a designed schema sketch, clearly
     marked designed.
- Status: mixed by block, each block labeled separately. A single
  panel-level status would lie about one of the two, so this panel is
  the one exception to the one-status-per-panel rule, and it says so
  on screen ("Two sources, two states").

### Panel 7: Knowledge brain

- Job: is the brain current, and can M3ta search it from here.
- Content: brain status from `BrainClient.status()` (`live`, the
  rea-mcp status map the Brain screen already renders); a search field
  that routes to the existing Brain screen with the query carried
  over (the dashboard does not grow a second search implementation);
  and a corpus state block, `snapshot` or `blocked` per item: Notion
  hub built (2026-11-01), vault mirror job not running, OpenKnowledge
  corpus import not done (the structural gap), Console Knowledge
  module specced, not built (specs/m3ta-os-console-knowledge.md).
- Ingest queue counts appear only if the snapshot carries them with a
  date. The dashboard does not read Notion directly; no Notion feed
  exists in the Console and the MVP adds none.
- Status: status block `live`, corpus block `snapshot`.

### Data contract: `DashboardState`

One new Codable type in ConsoleCore, following the `MeshState` shape
(codable, `Sendable`, loader with a bundled fixture plus a Settings
path override `dashboardStatePath`, loader errors surface as an error
state, never a silent fallback to stale data without the age shown).

Fields, all optional except `capturedAt` and `source`, so a partial
snapshot renders what it has and omits the rest:

| Field | Feeds | Notes |
| --- | --- | --- |
| `capturedAt`, `source` | All snapshot panels | Same names and age math as `MeshState` (`SnapshotAge`). |
| `briefLines` | Panel 1 | Pre-ranked lines with per-line `sourceTag`; the app re-ranks by the fixed rule order only if lines carry a `kind` (approval, calendar, blocked, knowledge, revenue). If `kind` is absent, lines render in file order. |
| `calendarNext` | Panel 1 | Title and start time only. No attendees, no locations, no notes. |
| `surfaces` | Panel 4 | Per-surface: name, state word, note, asOf. The app renders the words it is given and does not upgrade them. |
| `revenue` | Panel 5 | Ladder rows (name, price string, gate note) plus `verifiedRevenueLine` and `verifiedRevenueAsOf`. Price is a string, never a number the app formats into a claim. |
| `knowledge` | Panel 7 | Corpus items: name, state word, note, asOf. |
| `skillsBrain` | Panel 6 block 2 | One blocker line plus `asOf`. Nothing else until Phase 1 exists. |

Producer: out of scope for the MVP build, named here so the contract
is honest: a snapshot is produced by the same kind of job that produced
the mesh-state fixture (an agent-side export on a cadence), and until
a producer runs on a cadence, snapshot panels are exactly as fresh as
the last hand-made file, with the age on screen saying so. The bundled
fixture for first build is assembled only from facts already on record
in this spec's Current state, each with its date.

### Motion and the cinematic layer

The Design Masterpiece Pipeline applies: cinematic within the app's
existing language, not a second visual system.

- Hero: the ratified Th3 M3ta Way badge (SVG master from the brand
  kit, unchanged) at hero size, one glow treatment behind it, max one
  per surface per the theme rules. No nebula or gradient field competes
  with panel text.
- Motion set, closed list: (1) hero entrance, panels rise and fade in
  a 60ms stagger, once per screen appearance, never on refresh;
  (2) the voice orb pulse in `working` state only, driven by stream
  events; (3) number transitions on live counts (approvals pending,
  tools exposed) as instant crossfades, no counting animations;
  (4) panel hover and focus states as opacity and border changes only.
  Nothing else moves. No parallax, no scroll-driven effects inside a
  status tool, no looping ambient animation.
- Reduce Motion: every item above is replaced by its end state with no
  transition when `accessibilityReduceMotion` is on. Entrance stagger
  off, orb becomes a static filled state with the same meaning, counts
  swap instantly (they already do).
- Performance: animations run on the render thread's standard SwiftUI
  transitions; the dashboard adds no timers of its own. Live probes
  keep the app's existing refresh pattern (manual Refresh plus the
  JARVIS live view's interval where that view is used); the dashboard
  does not poll faster than the existing 10 second default anywhere.
- Static reliability floor: with JARVIS down and no snapshot file, the
  dashboard still renders every panel frame with its honest state
  (offline card for live blocks, "No snapshot loaded" for snapshot
  blocks). No blank screen, no spinner that never resolves. This is
  the native-app form of the pipeline's static-hrefs rule: content and
  state first, motion and liveness as enhancement.

### Brand application

- The badge is the brand kit's standard badge, unchanged, per the
  ratified rule. No new logo work in this spec.
- Colors: unresolved between the three systems in Current state, and
  deliberately so. The implementation step takes whichever system
  M3ta picks at resolve and expresses the dashboard entirely in that
  system's existing token names (`TMWTokens` if system 2, new
  `DashboardTokens` mirroring the brief's hexes if system 1). Two
  binding rules either way: every text-bearing pair the dashboard
  introduces gets a contrast test in `ThemeTests` style before the
  screen ships (the theme file already carries pair lists for exactly
  this), and status colors come from the semantic status tokens of the
  chosen system, never from brand accent colors.
- Type: system font today (Inter is named in tokens.json but not
  bundled; the dashboard does not bundle a font in the MVP). Numerals
  in counts use monospaced digits, as `StatusCard` already does.

## Failure modes

| Failure | Behavior |
| --- | --- |
| JARVIS offline on open | Live blocks show the existing offline pattern with Retry; snapshot panels render normally; the hero brief still renders from the snapshot. |
| Snapshot file missing or unreadable | Snapshot panels show "No snapshot loaded" plus the attempted path; live blocks unaffected. No silent substitution of the bundled fixture once a path override is set and fails: the error shows, as `BotStore` does when a live map fails (it falls back and says so; the dashboard instead shows the error state, because falling back to a stale fixture while claiming freshness is the failure this design exists to prevent). Deviation from `BotStore` behavior, recorded deliberately. |
| Snapshot older than 24 hours | Age line turns to the warn tone and brief lines from that snapshot are prefixed "As of <date>" in the hero. Data still renders; staleness is labeled, not hidden. |
| rea-mcp health has no `pending` field | Approvals strip shows "Pending count: Unknown". Never zero. |
| A surface row's state word is not in the vocabulary | The row renders the raw word with the `raw` tag style, as `StatusTag` already does for unknown statuses. |
| Reduce Motion on | All motion replaced by end states (see Motion). |
| Window at minimum size | Single column stack in the fixed panel order; hero compresses to badge plus greeting, orb remains visible. |

## Acceptance tests

Unit tests in Tests/ConsoleCoreTests/DashboardStateTests.swift:

1. Loader: a fixture with all fields decodes; a fixture with only
   `capturedAt` and `source` decodes and yields empty panels data.
2. Loader failure: a malformed file throws; a missing override path
   throws (no bundled fallback when an override is set).
3. Brief ranking: lines with kinds render in the fixed order
   (approval, calendar, blocked, knowledge, revenue) regardless of
   file order; lines without kinds keep file order; absent kinds leave
   no empty slot.
4. Age: a snapshot older than 24 hours reports stale; a fresh one does
   not; age text matches `SnapshotAge` formatting for the same input.
5. Revenue rendering data: the ladder rows decode as strings and the
   verified-revenue line carries its `asOf` date through to the view
   model unchanged.
6. Contrast: every text pair introduced by the chosen token set passes
   WCAG AA in `ThemeTests` style, for both appearances if the chosen
   system has two.

View-level checks (manual, on the Mac, recorded in the build PR):

7. Launch lands on Dashboard; sidebar shows the Command group; every
   existing screen still reachable and unchanged.
8. With JARVIS running: approvals count, JARVIS row, REA skills block,
   and brain status show live values with checked-at times.
9. With JARVIS stopped: offline states render per the failure table;
   the app does not hang and the snapshot panels still render.
10. Reduce Motion on: no entrance stagger, orb static, counts swap
    instantly; VoiceOver reads each panel's name, status word, and
    source line as one element per panel header.

Live acceptance:

11. Packaged app on the Mac opens on the dashboard and definition-of-
    done item 6 passes end to end. Before the run, the expected weak
    panels are recorded here: Panels 4 and 7, because their snapshot
    content is only as good as the first hand-made fixture.

## MVP vs later

MVP (this change): the Dashboard screen and its seven panels as
specced, `DashboardState` plus loader plus tests, the hero and motion
set, the default-on-launch change, and the Mac live verification.

Later, each its own change and its own gate: speech input and output
and the speaking avatar (Panel 2's designed half); the approvals queue
list and decision controls (needs the JARVIS list endpoint, then the
action-card flow); a snapshot producer on a cadence (agent-side job,
not app code); a model-written brief summary line (labeled, local
first); the Console Knowledge module build (its own spec); Skills
Brain registry panels beyond the blocker line (after the registry-of-
record ruling); per-offer revenue detail (after the G7 ledger exists);
an EGM Review tab using the runtime step (after `egm-goldfish` is
registered on the Mac).

## Dependencies and risks

- Depends on: nothing new for the MVP beyond the existing JARVIS
  loopback reads and a first `DashboardState` fixture. Every richer
  version depends on something named above as blocked or later.
- Brand decision risk: building against one token system and having
  the resolve step pick another is a token swap, not a redesign, by
  construction. The costlier risk is shipping a dashboard that quietly
  becomes a fourth brand surface; the contrast-test rule and the
  badge-unchanged rule are the controls.
- Stale-snapshot risk: the dashboard's biggest honesty risk is a
  snapshot that looks current. Age always on screen, warn tone past
  24 hours, and no fallback substitution are the controls. The
  residual risk is a producer that never lands, leaving the dashboard
  a well-labeled museum of its fixture date; the Later producer item
  is the fix and should be scheduled with the MVP, not after it.
- Scope risk: the voice panel invites scope creep toward a full voice
  assistant inside the Console. This spec's line is presence plus
  routing in the MVP; speech is a separate spec with its own privacy
  decisions.

## Open questions for M3ta's resolve step

1. Brand: which token system governs the dashboard: the brief's gold
   on black (system 1), the in-repo Cosmic Lightbody (system 2), or
   the house navy and gold (system 3)?
2. Default screen: is Dashboard the launch default, displacing
   Overview, or does Overview stay the default until the dashboard has
   lived a while?
3. Snapshot producer: who produces `DashboardState` and on what
   cadence: a scheduled agent job, or a manual export M3ta triggers?
4. Voice: when speech is specced, is the direction local-only speech
   processing, matching the local-first model rule?

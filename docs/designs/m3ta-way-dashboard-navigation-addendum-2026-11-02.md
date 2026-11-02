# Addendum: dashboard navigation contract and panel brainstorm

Status: addendum to docs/designs/m3ta-way-dashboard-2026-11-02.md,
written 2026-11-02 at M3ta's direct request. It answers his navigation
question ("will the panels be clickable and actually take me to the
project?") as a binding contract for the build, and records a
brainstorm of additional panels for his resolve step. Nothing here is
built yet unless a row says so. Where this addendum and the parent
spec disagree, this addendum wins on navigation only; everything else
in the parent spec stands.

## 1. Navigation / deep-link contract

### The three click behaviors

Every clickable element on the dashboard does exactly one of three
things. The behavior class is part of the element's design, shown in
its label or icon, never a surprise after the click.

| Class | Name | What happens on click |
| --- | --- | --- |
| (a) | INTERNAL | Opens a screen inside the Console (Today, Copilot, Brain, Bots, Mesh, and any future in-Console module). No app switch, no browser. |
| (b) | LAUNCH | Hands off to the owning app or workspace on the Mac, through Otto (the ruled central dashboard and launcher) or through the app's own registered URL scheme / deep link. The Console stays open behind it. |
| (c) | WEB | Opens the live web surface in the default browser (Digital HQ, Orbit, Paperclip, Plane, Linear, Cal.com). The URL always comes from the snapshot's `routeURL` field, never hard-coded in the app (parent spec rule, kept). |

Rules that bind all three classes:

- **No dead clicks (reliability floor).** If the target is not
  running, not installed, or its identifier is not yet known, the
  element renders its status capsule plus an explicit action ("Launch
  in Otto", "Open in browser", "Identifier pending") instead of a
  bare link that goes nowhere. This is the native form of the
  static-href lesson from the 2026-11-02 Digital HQ fix: a control
  that cannot work must say so on its face.
- **Fallback chain.** LAUNCH elements fall back in this order: Otto
  handoff, then the app's own deep link, then WEB if a web surface
  exists, then status capsule plus Launch action (no click target).
  The fallback in effect is the one the element renders; it never
  silently changes.
- **Panels route, they do not duplicate** (parent spec rule, kept).
  A click takes M3ta to the surface that owns the work. The dashboard
  never grows a second copy of a project's data to avoid a click.
- **Action-card levels apply.** Navigation and launch are read-level
  (L0/L1): opening a screen, an app, or a page performs nothing in
  the target. Any element whose follow-through would send, publish,
  purchase, deploy, or delete stays behind its existing approval
  gate (L3, or L4 for money movement, signatures, secrets, security
  overrides). Clicking a panel never performs a consequential action
  by itself, and no element in this contract is wired to one.
- **Link controls are real controls** (parent spec rule, kept):
  labeled buttons or rows with explicit targets, not whole-card click
  areas, so VoiceOver and keyboard routes match pointer routes.
- **Honesty labels travel with the mapping.** Each row below carries
  its state in the parent spec vocabulary (`live`, `snapshot`,
  `designed`, `blocked`). A `designed` row is specced here with no
  code and no feed yet. A `blocked` row names its blocker.

### Panel mapping (the seven panels)

| Panel | Click target | Class | Destination identifier known today | State |
| --- | --- | --- | --- | --- |
| 1. Today / hero brief | None (it is the summary) | n/a | n/a | As parent spec |
| 2. Voice presence | Copilot screen | (a) INTERNAL | Console screen "Copilot" (exists today) | Designed (route exists in the app; the panel is new) |
| 3. Approvals strip | Copilot screen, Runtime status tab (where the pending count already renders) | (a) INTERNAL | Console screen "Copilot" | Designed; queue detail itself stays `blocked` per parent spec |
| 4a. Command surfaces, JARVIS row | Copilot screen, Runtime status tab | (a) INTERNAL | Console screen "Copilot" | Designed |
| 4b. Command surfaces, Otto row | Otto app on the Mac | (b) LAUNCH | Otto.app (`io.openotto.desktop`, /Applications/Otto.app); control surface `ottoctl` / `otto-mcp` in the app bundle | `blocked`: launch renders as a status capsule plus Launch action until M3ta's in-app scoped grant lands; the Console has no Otto feed |
| 4c. Command surfaces, Orbit row | Orbit workspace in the browser | (c) WEB | Snapshot `routeURL` (the Orbit endpoint URL is a credential and is never printed or hard-coded) | `snapshot` |
| 4d. Command surfaces, Paperclip row | Paperclip board in the browser | (c) WEB | Mac/VM boards at localhost:3100 per box (per-box snapshots, not sync); company Th3 M3ta Way `72a661f6-b1fc-4fdb-9167-1c96bd8360b7` | `snapshot` |
| 4e. Command surfaces, Plane row | Plane project in the browser | (c) WEB | Snapshot `routeURL`; workspace inventory 45 projects / 598 issues (2026-11-02) | `snapshot` |
| 4f. Command surfaces, Linear row | Linear project in the browser | (c) WEB | Snapshot `routeURL`; team Th3 M3ta Way `a14a4437-e3c3-4ac6-b126-26e4d23aaa9f` | `snapshot` |
| 5. Revenue engine | None in the MVP (parent spec). Later: each ladder row routes WEB to the offer's live page only when one exists and selling gates are open | (c) WEB, later | Digital HQ (live): https://digital-hq-kinddom-m3tas-projects.vercel.app/ ; booking: cal.com/c0achm3ta/30min | `designed` (later item; gates closed today) |
| 6a. Skills Brain, REA block | Copilot screen, Runtime status tab | (a) INTERNAL | Console screen "Copilot" | Designed |
| 6b. Skills Brain, registry block | None | n/a | Registry-of-record ruling pending | `blocked` |
| 7. Knowledge brain | Brain screen, search query carried over | (a) INTERNAL | Console screen "Brain" (exists today) | Designed |

### Venture mapping (seven ventures + Builder Brokerz + services lane)

Venture rows live in Panel 4's orbit/venture area and in any future
venture strip. Each row's primary click follows the same contract.

| Venture row | Click target | Class | Destination identifier known today | State / fallback |
| --- | --- | --- | --- | --- |
| M3ta-OS | Otto profile for the platform workspace | (b) LAUNCH | Otto profile "M3TA-0S" | `blocked` on the Otto grant; fallback WEB to Digital HQ |
| Qu3bii | This Console (Qu3bii's own surface) | (a) INTERNAL | Console Dashboard screen itself | Designed; no app switch needed |
| Hermes | Otto profile for the voice layer | (b) LAUNCH | Otto profile "Herm33z TMW" | `blocked` on the Otto grant; fallback: status capsule only (no web surface) |
| M3ta'z a3y3 Lab | Otto profile for the Lab | (b) LAUNCH | Otto profile "M3TA'Z A3Y3 LAB" | `blocked` on the Otto grant |
| Th3 M3ta-V3rse | Owning workspace | (b) LAUNCH | Identifier TBD at build (no Otto profile under this name in the verified 11) | `designed`; renders capsule plus "Identifier pending", no click target |
| C0ACH M3TATRON / C0ACH M3TA | Otto profile for the personal brand | (b) LAUNCH | Otto profile "C0ach M3ta" | `blocked` on the Otto grant; fallback WEB to Digital HQ |
| AI Architect.ai | Owning workspace | (b) LAUNCH | Identifier TBD at build (no Otto profile under this name in the verified 11) | `designed`; capsule plus "Identifier pending" |
| **Builder Brokerz** | **Otto profile "Builder Brokerz"** | **(b) LAUNCH** | **Otto profile "Builder Brokerz" (one of the verified 11)** | **`blocked` on the Otto grant today; see the worked example below** |
| Services lane (AI Architect.ai offers) | Digital HQ + booking page | (c) WEB | https://digital-hq-kinddom-m3tas-projects.vercel.app/ and cal.com/c0achm3ta/30min | `live` web surfaces; selling itself stays gated (WS-06 copy approval + live Stripe) |

Secondary routes per venture (shown as small labeled controls, never
hidden in the primary click): the venture's Paperclip project (WEB,
snapshot `routeURL`), its Plane delivery project (WEB, snapshot
`routeURL`), and its CopilotKit Intelligence project where one exists
(projects 9054 th3-m3ta-way, 15527 m3ta-os-console, 17383 Timeless
Fitness, 17384 Lola Ybor City, 17385 Synergy Haven, 17386 Sonya
Johnson, 17387 Edge Hydration, 17388 Meta Logistics; Builder Brokerz
rides on 9054; 11170 copilot-oracle is orphaned and gets no route
until M3ta's wire-or-delete call).

### His example, answered concretely: Builder Brokerz

M3ta clicks the Builder Brokerz panel. In the full build:

1. The click is class (b) LAUNCH. The Console asks Otto to bring up
   the **"Builder Brokerz" Otto profile**, which is that venture's
   workspace: its apps, agents, and surfaces in one place. The
   Console stays open behind it. Yes, it pulls up Builder Brokerz
   itself, not a picture of it.
2. Today, before his grant: Otto control waits on M3ta's in-app
   scoped grant inside Otto (Otto is verified running on the Mac;
   the grant tap is his). Until then the panel does not pretend: it
   shows its `blocked` capsule ("Otto grant pending") and offers the
   working fallbacks instead: WEB to the Builder Brokerz Paperclip
   board (company `1d5b0f3c-2927-4636-9482-8847ef29f652`, Onboarding
   project) and the venture's other snapshot routes.
3. The click never sends, publishes, or changes anything in Builder
   Brokerz. It opens the workspace at read level. Work inside it
   follows the same action-card gates as always.

The same shape holds for every venture row: INTERNAL when the work
lives in the Console, LAUNCH through Otto when another app owns it,
WEB when the live surface is a page, and an honest capsule plus a
working fallback whenever the first route is not available yet.

### What can deep-link today vs designed vs blocked (summary)

- **Works today, outside the dashboard:** the WEB destinations that
  are live now (Digital HQ, Cal.com booking, Paperclip boards,
  Plane, Linear, Orbit in the browser) and the Console's existing
  internal screens (Copilot, Brain). The dashboard's routing controls
  themselves are new code.
- **Designed:** every INTERNAL route from the new panels, the venture
  strip, LAUNCH fallback chains, and the two TBD venture identifiers
  (Th3 M3ta-V3rse, AI Architect.ai) to be resolved at build.
- **Blocked:** all LAUNCH behavior through Otto, on one named
  blocker: M3ta's in-app scoped grant. The approvals queue detail and
  the Skills Brain registry routes stay blocked on their parent-spec
  blockers (no JARVIS list endpoint; no registry-of-record ruling).

## 2. Panel brainstorm: candidates beyond the seven

Each candidate is grounded in records that exist today. Data source
and honesty label are stated per panel, in the parent vocabulary. A
panel with no real data source does not get invented data; it gets
its true label or it gets cut.

| # | Candidate panel | Job | Data source (verified) | Label | Verdict |
| --- | --- | --- | --- | --- | --- |
| B1 | Money Watch | Every billing deadline and card state in one strip, so no renewal fails silently again | Gmail billing alerts across his accounts + the subscription audit (tracker goal_96b3864cc584, monthly rescan). On record now: m3tabuz Workspace suspends Nov 6 (unpaid, closed-account card); Google One fix by Nov 5; Google Cloud billing already suspended, termination risk ~Dec 1; Orbit Agency $249 renews Nov 3; MLG Thread Bank Visa ending 7098 is primary and working (paid the $29.04 Workspace balance Nov 1); Visa ending 8006 is on a closed bank account; Visa ending 1845 is failing across services; Strawberry $20 and Bezalel $29 renew Nov 19 | `snapshot` (producer-fed, dates on screen) | **Include, rank 1** |
| B2 | Clients & Build-Outs | The seven project build-outs as client rows: Timeless Fitness, Builder Brokerz, Lola Ybor City, Sonya Johnson, Synergy Haven, Edge Hydration, Meta Logistics | Build-out packs in ~/workspace/project-buildouts/ (INDEX-2026-10-31.md; 48 decisions queued, nothing sent). Each row routes per Section 1 (Otto profile where one exists, else WEB/Paperclip) | `snapshot` | **Include, rank 2** |
| B3 | Content Engine | Pipeline state for the content and affiliate engine: stage status, TikTok Shop registration, scheduled posts | Invocation map's 11-stage pipeline (~/workspace/goals/ai-content-engine-that-promotes-everything-and-grows-income/files/full-stack-invocation-map-2026-11-02.md); TikTok Shop: registration in progress at Step 1 verification (Paperclip THM-241 blocked on M3ta); EDGE post slots Nov 3 / 5 / 7 at 1:00 PM ET with 11:00 AM preflights; Postiz stack up on the Mac | `snapshot`, with `blocked` sub-rows where a stage is gated (TurboUGC plan gate, Postiz API from the sandbox) | **Include, rank 3** |
| B4 | Security & Access | Open security confirmations in one place, closing only on M3ta's word (a reaction never closes one) | Gmail security alerts + triage state. Open now: Nov 1 Fold6 sign-in to the business account; Nov 1 Notion new-device logins (x3); Nov 1 Impact login (Palm Bay); Nov 2 Facebook new-device login; Nov 2 Notion Calendar data-access grants (two accounts); Nov 2 VS Code / Spacefast grant (expires Dec 2); two LactiGo password-reset requests | `snapshot` | **Include, rank 4** |
| B5 | Comms / Inbox | Triage state across all 13 accounts: what cleared the bar, what is waiting | Inbox triage job (every 30 min; state file ~/workspace/goals/m3ta-command-center/hidden_files/inbox-triage-state.json; flagged count 2,072 as of Nov 2, 7:40 AM). VIP/deadline/money/security bar already defined | `snapshot` | **Include, rank 5** |
| B6 | Community & Sankofa | The ministry and community lane: tribute progress, event dates, held items shown as held | Orbit project "Sankofa House Lead Follow-Up" (slug sankofa-house-followup) + Paperclip tribute project (THM-231 to THM-236). On record: Suno pilot generated (4 versions, Nov 1); Give Thanks Weekend Nov 21-22; Virtual Sisterhood Tuesdays Nov 3-24, 7:30 PM ET; the personal message to the Chieftess is HELD by M3ta's ruling and renders as held, never as a send button | `snapshot` | Include, next round after the top 5 |
| B7 | Florida Claims | Claim status without inventing movement: Bloodwashed Records and HCA | Claims records (goal florida-claim-board-and-follow-up-loop). Bloodwashed: $20,472.77 via The Graham Group, ref B 144599416, agreement signed and mailed Jul 7, 2026, silent since; HCA: $47.00, property 221973565, form prepared to Step 5, filing unconfirmed. Status checks are M3ta's own action on the official channels; the panel is read-only and never performs or implies a check | `snapshot`, mostly static between M3ta's own updates | Include as a small static row inside Money Watch rather than its own panel: the data is real but changes rarely, and a full panel would overstate its motion |
| B8 | Health | Activity, sleep, recovery at a glance | A real source exists: Apple Health and Health Connect are connected connectors. But sync coverage from his devices is unverified, and the Console has no feed from either | `designed` (source real, coverage unverified, no Console feed) | Cut from the next round. Revisit only after a sync-coverage check verifies what actually arrives; until then any number on screen would be a guess wearing a label |

Cut without a row: a generic "social stats" panel (no verified feed
exists for it in the Console's reach; Postiz records were unreachable
from the sandbox on Nov 1) and a "news / intel" panel (the Intel Lane
already lives in the brief lines and the Knowledge panel; a second
copy would duplicate, and panels route, they do not duplicate).

### Ranked top 5 for the next build round

1. **B1 Money Watch.** The Nov 5 / Nov 6 deadlines are days away and
   every fact it needs already exists in the audit records. Highest
   cost-of-absence of any candidate: a missed row here is a suspended
   account.
2. **B2 Clients & Build-Outs.** Turns the dashboard from a systems
   surface into the client surface M3ta actually asked about: each
   row is a Section 1 route into that client's workspace, and the
   48 queued decisions get a visible home.
3. **B3 Content Engine.** The revenue engine's working half. Panel 5
   shows the ladder and the gates; this panel shows the machine that
   is supposed to climb it, stage by stage, with its gates labeled.
4. **B4 Security & Access.** Seven open confirmations are currently
   scattered across morning briefings. One panel, closing only on
   his word, ends the scatter.
5. **B5 Comms / Inbox.** The triage job already produces this state
   every 30 minutes; the panel is mostly a rendering job on an
   existing feed, the cheapest of the five to build honestly.

Build order note: B1 to B5 are all `snapshot` panels on the existing
`DashboardState` contract (new optional fields, same loader, same age
rules). None of them needs a new live feed, a new endpoint, or the
Otto grant. They can ship in the same round as the parent spec's MVP
follow-up without touching its blocked items.

## Open questions added by this addendum

1. Venture identifiers: Th3 M3ta-V3rse and AI Architect.ai have no
   verified Otto profile in the current 11. At build, are they new
   Otto profiles, or do they ride on an existing one (for example
   M3TA-0S)?
2. Panel round 2: does M3ta approve B1 to B5 as the next round, with
   B6 (Community & Sankofa) as the sixth, and B7 folded into B1 as
   specced here?

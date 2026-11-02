# Addendum 2: tabs, hero ticker, social section, and app integrations

Status: second addendum to docs/designs/m3ta-way-dashboard-2026-11-02.md.
Companion to docs/designs/m3ta-way-dashboard-navigation-addendum-2026-11-02.md
(addendum 1). Written 2026-11-02 at M3ta's direct request (voice): use
the full inventory of app-building tools and capabilities to build out
more features, interconnectivity, and automation; integrate Hermes,
OpenClaw, OpenBot, and OpenDots; put QB, Hermes, Meta OS, and A.D.A.M.
across the top as tabs; make the hero live and pulsing with a
stock-channel-style ticker of system stats; add social media heroes
and sections with activity, posts, and analytics.

Where this addendum and the parent spec disagree, this addendum wins
on the four subjects it covers (tab bar, ticker, social section, the
four app-integration rows). Everything else in the parent spec and
addendum 1 stands, including the status vocabulary (`live`,
`snapshot`, `designed`, `blocked`), the no-dead-clicks floor, and the
rule that no number appears unless it traces to a named source.

Governing principle for all wiring in this addendum: the
full-capability invocation rule (M3ta, 2026-11-02): every installed
skill, tool, model, repo, and connector that can improve a deliverable
is actively invoked, nothing capable sits idle, at the level the piece
needs. It is subject to the Best-Configuration Rule (2026-11-01):
standing configuration rules are defaults, and the safeguards are not
defaults (approval gates for consequential external actions, never
auto-post outside the phased ruling in Section 3, confirmed-only
business terms, secret handling).

## 1. Top tab bar: QB, Hermes, Meta OS, A.D.A.M.

### Shape

- A persistent tab bar sits at the top of the Dashboard screen, above
  the panel stack, present in every Dashboard state including the
  failure states in the parent spec's table. It is a lens over the
  same `DashboardState`, not four separate dashboards and not four
  copies of the data. The parent rule holds: panels route, they do
  not duplicate.
- The tab bar is part of the Dashboard screen only in this addendum.
  It does not replace the sidebar, and it does not change any existing
  screen. How it interacts with the launch-default question is stated
  under State rules below and in Open questions.
- Each tab keeps the parent layout order for the panels it shows
  (hero first, approvals strip directly under it where the tab carries
  it, then its grid). Tabs filter and re-rank; they never hide the
  approvals strip on the QB tab, because approvals are the one element
  that asks M3ta to act.

### The four tabs

| Tab | Actor and role | Contents (one line) |
| --- | --- | --- |
| QB | Qu3bii, the executive orchestrator: strategy, routing, policy, delegation | The seven parent panels as specced (Today hero, voice presence, approvals strip, command surfaces, revenue engine, Skills Brain, knowledge brain): the orchestration home and the approval surface. |
| Hermes | The human-facing interface: voice, capture, comms, presence, approvals delivery | The voice presence panel grown to a full tab: text chat route, comms surface rows (WhatsApp, iMessage, AgentMail, Pluto), and the speech roadmap rendered with its true `designed` label. |
| Meta OS | M3ta-OS, the sovereign platform: modules, runtimes, infrastructure | The platform view: the 11 M3ta-OS modules, the Console's own screens and runtimes (JARVIS, rea-mcp), CopilotKit Intelligence projects, the EGM runtime step state, and the OpenDuet stack state. |
| A.D.A.M. | The specialist agent workforce (Agentic Digital Automation Mesh) | The workforce view: agent census rows by home system, the four A.D.A.M. autonomy levels as the tab's organizing spine, and per-agent state where a source exists. |

Tab contents in detail:

**QB tab.** Exactly the parent spec's Dashboard: Panels 1 to 7 in
parent order, hero with the ticker (Section 2) fused under it, the
approvals strip under the hero. Nothing moves. This tab is the
default view (see State rules).

**Hermes tab.** Contents, each block labeled on screen:
- Voice presence (parent Panel 2, unchanged): the orb, the shared
  `ChatRunStore` state, the truth line about speech. Capsules:
  "Presence: live" and "Speech: designed", as the parent spec rules.
- Chat route: a labeled control to the Copilot screen (addendum 1
  class (a) INTERNAL). The tab does not grow a second chat surface.
- Comms surface rows, `snapshot`, from `DashboardState` only, each
  with its date: WhatsApp (connected, per M3ta's statement
  2026-11-01); iMessage via Bezalel (paired, outbound passed, inbound
  unconfirmed, audit 2026-10-18/19) and via Pluto (paired 2026-10-20
  to his number, instance on the free plan); AgentMail inboxes (six
  live, org on record; the paperclip@agents.th3m3taway.com inbox is
  blocked on four Cloudflare DNS records). Rows render the record and
  its date; none of these is a Console feed, and the tab claims none.
- Approvals delivery note: Hermes is the approvals delivery layer in
  the architecture (capture, clarify, brief, approvals, presence);
  the decision surface itself stays on the QB tab's approvals strip.
  This tab links to it (class (a) INTERNAL), it does not duplicate
  the strip.

**Meta OS tab.** Contents:
- Module grid: the 11 M3ta-OS modules (including Command Center,
  Knowledge Vault, Agent Studio, Revenue Hub, Client OS, Content
  Engine), rendered from `DashboardState`, `snapshot`, each module a
  row with its state word. Modules with no verified state render
  "Unknown", never a guessed state (parent Definition of done 3).
- Runtime rows, `live` where the Console already reads them: JARVIS
  health and model route, rea-mcp, CopilotKit runtime, from the
  parent spec's allowed loopback read set, with checked-at times.
- CopilotKit Intelligence projects, `snapshot`: the nine verified
  projects (9054 th3-m3ta-way, 15527 m3ta-os-console, 17383 Timeless
  Fitness, 17384 Lola Ybor City, 17385 Synergy Haven, 17386 Sonya
  Johnson, 17387 Edge Hydration, 17388 Meta Logistics, and
  copilot-oracle 11170 rendered as orphaned, per the 2026-11-02
  audit). The orphan row carries no route until M3ta's wire-or-delete
  call (addendum 1 rule, kept).
- EGM runtime step row, `blocked` until the agent is registered:
  "egm-goldfish registration is a Mac-side step in M3ta's session"
  (parent spec and the EGM spec record). The dashboard does not
  depend on it.
- OpenDuet stack row: see Section 4 (3 of 5 services healthy at the
  2026-11-02 activation, two services exited on the missing OpenAI
  key). `snapshot` with the activation date.

**A.D.A.M. tab.** Contents:
- Autonomy spine: the four A.D.A.M. autonomy levels as recorded in
  the ecosystem definition (copilot, approval, supervised,
  autonomous), shown as the tab's header strip. These are A.D.A.M.'s
  levels. The action-card levels L0 to L4 in the parent spec are a
  separate vocabulary for single actions; the tab does not merge the
  two, and no row silently converts one into the other.
- Workforce census rows, `snapshot`, each row one home system with
  its count and count date, from `DashboardState` only: Orbit (201
  agents, 14 departments, PUSH-SEQUENCE completed 2026-10-27);
  Paperclip Th3 M3ta Way board (3 agent records at the 2026-11-01
  census: Qu3bii idle, Orbit-TMW in error, Summarizer in error, the
  two error states rendered as recorded, not hidden); Hyperagent (13
  agents on the account, observed 2026-11-02). A row whose census is
  older than its stated date allows renders with its age, per the
  parent staleness rules.
- Per-agent detail: `designed`. No Console feed lists agents from any
  of these systems today, and this addendum does not invent one. The
  tab shows census rows and routes out (addendum 1 classes) rather
  than fabricating a roster.

### Tab interaction with the navigation contract

- Clicks inside any tab follow addendum 1 unchanged: class (a)
  INTERNAL opens a Console screen, class (b) LAUNCH hands off through
  Otto or the app's deep link, class (c) WEB opens the live web
  surface from the snapshot's `routeURL`. The tab bar adds no fourth
  class.
- Switching tabs is view state only. It performs no action in any
  system, triggers no collection (parent Definition of done 2 binds
  every tab, not only the QB tab), and is read-level under the
  action-card vocabulary.
- A panel that appears under more than one tab (voice presence under
  QB and Hermes; command surfaces under QB and Meta OS) is the same
  component reading the same state, per the no-duplication rule. Its
  status capsules are identical in both places because its source is.

### Active-tab state rules

- Exactly one tab is active at a time. The active tab is rendered
  with the chosen token system's accent treatment (parent Brand
  application rules apply; status colors never come from brand
  accents, and the tab treatment is not a status).
- On launch, the Dashboard opens on the QB tab. Tab selection is held
  in memory for the launch and is not persisted across launches in
  this addendum; persistence is a Later nicety, not a behavior M3ta
  has ruled on.
- Tab selection survives the parent spec's refresh cycle (toolbar
  Refresh, `.consoleRefresh`, the probe interval) and survives a
  `DashboardState` reload or failure: a failed snapshot never bounces
  M3ta to another tab or another screen.
- With Reduce Motion on, tab switches are instant state changes
  (parent Motion rules). VoiceOver and keyboard order: tab bar first,
  in the order QB, Hermes, Meta OS, A.D.A.M., then the active tab's
  panels in their layout order.
- If the resolve step makes Dashboard the launch default (parent Open
  question 2), the tab bar is the first thing under the hero region
  he lands on, on the QB tab. If Overview stays the default, nothing
  in this section changes; the tab bar exists when he opens Dashboard.

## 2. Hero ticker

### Job and placement

A single-line ticker runs under the hero frame on the QB tab,
stock-channel style: a slow, continuous scroll of short system stats,
each item carrying its source tag, with the snapshot date rendered at
both ends of the strip. It is a rendering of data the dashboard
already holds. It collects nothing, and it is the second visual
element of the hero, not a new panel: it gets no panel frame, no
capsule of its own; the hero's `snapshot` capsule and "Brief as of"
line cover it, and its own date line (below) makes its age explicit
on the strip itself.

### Data contract

One new optional field on `DashboardState`, produced and loaded by
the same machinery as every other field (same loader, same age
rules, same failure behavior):

```swift
public struct TickerItem: Codable, Sendable, Equatable {
    public let text: String        // required; the full item as rendered, number included
    public let sourceTag: String   // required; rendered after the item
    public let asOf: String        // required, ISO-8601; the date of the underlying record
}
// DashboardState gains: public let tickerItems: [TickerItem]?
```

Rules:
- The ticker renders `tickerItems` in file order, looped. Ranking is
  the producer's, fixed at capture time; the app does not re-rank
  ticker items with a model or with code beyond rendering.
- Every item's number traces to its named record (parent Definition
  of done 3). An item whose record is superseded is removed by the
  producer at the next capture, not edited in place by the app.
- The strip opens and closes with a date segment rendered from
  `capturedAt`: "Snapshot <date>". The word "live" never appears on
  the strip. Until a real feed exists, the ticker is a snapshot
  scroller, and it says so on its face.

### What scrolls: the verified inventory

The first producer run assembles items only from these records, each
with its date. This list is the ceiling for the first build, not a
floor: an item with no current record does not scroll.

| Item (shape) | Record | Date |
| --- | --- | --- |
| Orbit: 201 agents, 14 departments | Orbit PUSH-SEQUENCE completion record | 2026-10-27 |
| Orbit CRM: 866 people | Same reconciliation record | 2026-10-27 |
| Bezalel: 86 tools, 10 connectors active | Bezalel capability audit | 2026-10-18/19 |
| Plane: 45 projects, 598 issues | Plane live inventory for the workflow strategy | 2026-11-02 |
| Paperclip (VM): 27 projects, 228 issues | Paperclip ecosystem census (28 projects after 2026-11-02 additions; the producer uses the count from its capture record, not this table) | 2026-11-01 |
| Approvals pending: count from rea-mcp /health | The one live item class: rendered from the probe the app already makes, labeled with its checked-at time, and visually marked as the strip's only live segment | live probe |
| Orbit Agency renewal: Nov 3, $249/mo | Orbit billing verified in the workspace record (confirmed figure, not a negotiated term) | verified 2026-10-27 |
| Orbit check-in: Tue Nov 3, 11:00 AM ET (Jonatan accepted) | Business calendar series record | 2026-11-01 |
| Google One: payment fix by Nov 5 | Billing alert record, personal account | 2026-11-01/02 |
| m3tabuz Workspace: suspends Nov 6 if unpaid | Billing alert record; end state unconfirmed with M3ta | 2026-11-01 |
| Verified revenue to date: $0 (empire audit) | Empire audit headline | 2026-11-01 |

Deadline items scroll only while they are in the future relative to
`capturedAt`; the producer drops a deadline item at the first capture
after its date, and the resolution (paid, cancelled, suspended) is a
new item only if a record states it.

### Cadence and the snapshot label

- The ticker's cadence is the snapshot's cadence. It inherits parent
  Open question 3 (who produces `DashboardState` and on what
  cadence) in full: until a producer runs on a cadence, the ticker is
  exactly as fresh as the last capture, and its date segment says so.
  This addendum adds one follow-on question (Open questions, item 1)
  rather than picking a faster cadence silently.
- No ticker-only refresh exists. The strip never polls, never fetches,
  and never updates between snapshot loads except the single live
  approvals segment, which updates when the app's existing probe
  cycle updates the approvals strip (same value, same checked-at
  time, rendered in both places from the same probe result).

### Motion rules

This addendum amends the parent spec's closed motion list by adding
exactly one item, recorded here as a deliberate amendment in the same
way addendum 1 amended navigation:

- (5) Hero ticker scroll: one linear scroll loop of the ticker strip,
  constant speed, no bounce, no acceleration. It pauses while the
  pointer hovers or the strip has keyboard focus, and while any panel
  on the screen is being interacted with. It is the only ambient
  motion on the screen; the parent rule that the orb pulses only in
  `working` state is unchanged, and the two never compete for the
  same region (orb in the hero frame, ticker under it).
- Reduce Motion replacement: with `accessibilityReduceMotion` on,
  the strip does not scroll. The same items render as a static,
  wrapped, two-line-at-most summary block under the hero, in file
  order, fully readable, with the same date segment. No information
  is motion-gated.
- The hero glow allowance is unchanged: the ticker adds no gradient,
  no nebula, no second glow. Its background is the chosen system's
  surface token, its text the text token, its source tags the muted
  token, each pair covered by the parent contrast-test rule before
  the screen ships.

## 3. Social media section

### Shape

One new panel for the QB tab, placed after Panel 5 (Revenue engine)
in the grid, plus a hero treatment: the section's header row carries
up to three "hero" cards, one per featured account, each card showing
the account, its platform, its latest verified counts with their
`asOf` date, and one featured post (the account's own top post by the
platform connector's own insight read, where that read exists). Below
the heroes: an activity block (recent posts and scheduled posts) and
an analytics block (per-platform metric rows). Every block carries
its own capsule; the panel never averages them (parent rule).

Hero accounts are the accounts the producer names in the snapshot,
drawn from M3ta's verified handle inventory (core @th3_m3taway and
the approved lane handles on record). The panel does not choose hero
accounts with a model, and an account with no verified read does not
get a hero card.

### Data contract

One new optional field, same loader and age rules:

```swift
public struct SocialState: Codable, Sendable, Equatable {
    public let accounts: [SocialAccount]?   // hero cards + analytics rows
    public let activity: [SocialPost]?      // recent + scheduled posts
}
public struct SocialAccount: Codable, Sendable, Equatable {
    public let platform: String             // required
    public let handle: String               // required
    public let followers: Int?              // with followersAsOf required if present
    public let followersAsOf: String?
    public let windowLabel: String?         // e.g. "last 28d" for insight rows
    public let metrics: [SocialMetric]?     // named metrics only, see below
}
public struct SocialMetric: Codable, Sendable, Equatable {
    public let name: String                 // the connector's own metric name
    public let value: String                // string, never reformatted into a claim
    public let asOf: String                 // required, ISO-8601
}
public struct SocialPost: Codable, Sendable, Equatable {
    public let platform: String             // required
    public let stateWord: String            // published | scheduled | draft
    public let text: String                 // required; post text or its first line
    public let when: String                 // required, ISO-8601 (posted or scheduled time)
    public let sourceTag: String            // required
}
```

The example values in this addendum are structural only. No metric
value, follower count, or engagement figure is stated anywhere in
this section, because no social insight read for the Console exists
yet; the first producer run fills the contract from the routes below
or leaves the field out.

### Data routes: what is real today

The Console has no social feed, and this addendum adds none. Every
route below is a producer-side read (an agent-side job on the
snapshot cadence) or a route out. Verdicts are per platform, from the
connector records as they stand on 2026-11-02:

| Platform / route | What the connector actually does (verified in its doc) | Panel verdict |
| --- | --- | --- |
| Instagram (connected) | Reads profiles, posts, comments, stories, feeds, saved items, and insights. Account insights: `analytics-account-insights` over rolling windows (last 7, 14, 28, 90 days) and `account-insights` over explicit periods; per-post lifetime metrics via `individual-post-insights` for owned posts | Source route `live` (outside the Console); panel block `snapshot`. Metrics the analytics rows may name: the account-insight metrics the connector returns for the chosen window, and per-post lifetime metrics for the featured post. The producer reads them; the panel renders them with window and date |
| Facebook (connected) | Reads the user's Pages (`pages list`), Page insights (`pages account-insights`), Page posts (`pages posts list` / `get`), plus personal profile, feed, groups, and Marketplace surfaces | Source route `live`; panel block `snapshot`. Analytics rows name Page-level insight metrics from `pages account-insights` and post rows from `pages posts list`. Personal-profile analytics are not a connector capability and are not specced |
| Threads (connected) | Reads profiles, posts, replies, feeds, activity, insights (`insights-overview`), trends, and search | Source route `live`; panel block `snapshot`. Analytics rows name the `insights-overview` metrics for the account; the trends read may feed one activity row labeled as a platform trend, never as his performance |
| TikTok | No analytics connector route exists. The TikTok Shop Seller Center is a commerce surface (registration in progress at Step 1), not an analytics feed for his accounts | `blocked` for analytics, named on the block: "No TikTok analytics route exists." Shop registration state belongs to addendum 1's Content Engine panel (B3), not here; this panel does not duplicate it |
| Postiz (Mac, scheduler) | His self-hosted scheduler on the Mac. Stack verified up (port 4407 listening, 2026-11-01). The Nov 1 preflight from the sandbox got HTTP 403: credential not available to the sandbox. Two moves are his alone per the Postiz skill record: connect Instagram/Facebook in Postiz Channels, and generate the API key in Settings and drop it in the vault | Scheduled-posts block `blocked` from the sandbox route, blocker named on screen. Once the key lands and Channels are connected, the same block becomes a producer read (`posts list`) and renders `snapshot`. The stack being up is not the block being live, and the panel labels them separately |
| Zernio / Mixpost | Zernio is retired (2026-09-25, 2-account free cap). Its catalog note names Mixpost as the replacement; the Postiz skill record is the later word: Mixpost Lite is parked and Postiz is the standing scheduler route | No panel route. Neither system is specced as a data source anywhere in this section |

Posting, in every block: preparing drafts and scheduled posts is
L1/L2 work behind the existing per-post approval; publishing is L3.
Auto-post stays under M3ta's phased ruling (2026-11-02): off until
the system is proven (working end to end, analysis and A/B comparison
running, commissions and payments tracked), then set to auto-post by
his word. This panel displays and routes; it never publishes, and no
element in it is an auto-post switch.

### What the section never does

- No cross-platform rollup score, no combined follower total, no
  growth arrow without two dated reads from the same route. A trend
  is two snapshots or it is not rendered as one.
- No competitor or third-party analytics. The connectors' insight
  reads cover his own accounts; other accounts are public profile
  data only, and this panel shows none of it.
- No engagement number without its window and date on the row.

## 4. App integrations: Hermes, OpenClaw, OpenBot, OpenDots

Rows in addendum 1's mapping format (click target, class,
destination identifier known today, state). These four join Panel 4's
command surfaces as rows and, where a tab exists, as that tab's
route targets. Grounding is per row; the full-capability invocation
rule (header) is why each app gets a row at all, and the
Best-Configuration Rule is why a retired or stopped app gets an
honest row instead of a forced wiring.

| App | Click target | Class | Destination identifier known today | State today |
| --- | --- | --- | --- | --- |
| Hermes | Voice presence and chat (its Console surfaces); Otto profile for its workspace | (a) INTERNAL for presence/chat; (b) LAUNCH for the workspace | Console screens "Copilot" and the Dashboard Hermes tab; Otto profile "Herm33z TMW" (one of the verified 11) | Mixed, labeled per block: text chat `live`; speech `designed` (no speech surface is wired into the Console or JARVIS today, parent spec); LAUNCH `blocked` on the Otto grant. Hermes is first-class and reactivated in the architecture; this row routes to what exists and names what does not |
| OpenClaw | None in the MVP | n/a (status row only) | VM gateway health endpoint, checked by the standing watchdog (30-minute cadence) | `snapshot` status row: gateway verified healthy by the watchdog on 2026-11-01 (health returned ok/live, including the run that restored its missing service file). OpenClaw is retired as a core dependency (2026-07-18); the 2026-09-13 re-integration direction stands as baseline installed, first-run gate incomplete, no autonomous execution. The row presents it exactly that way: a studied capability pattern with a live gateway, not a core dependency, not a route the dashboard depends on, and no click target until M3ta rules otherwise |
| OpenBot | Its own surface where it runs (the OpenDuet fork track) | (c) WEB to the running app surface | Live deployment `~/repos/OpenDuet` on the Mac (branch agent/k0ad33/hub-pointer); the legacy openbot-tmw compose deployment on the Mac | Split state, never merged: OpenDuet (the live fork track) `snapshot`, 3 of 5 services healthy at the 2026-11-02 activation, agent-bot and agent-langgraph exited on the missing OpenAI key, which also gates activation stages 2 to 4. The legacy openbot-tmw deployment: stopped, not removed, on 2026-11-02 to free ports; retire-or-keep is M3ta's call, and the row renders "stopped, decision pending", not a route. OpenBot and OpenDuet are not the same row and are never presented as one system |
| OpenDots | The app on the Mac | (b) LAUNCH | Runs from `~/repos/OpenDots` on the Mac; no Otto profile under this name in the verified 11 | `blocked`, two named items from the 2026-11-02 record: bring-up still owed, and the CPK_INTELLIGENCE_API_KEY paste still owed. Until both land, the row renders its capsule plus those two items and no click target (addendum 1 no-dead-clicks rule). After bring-up, its class and identifier are recorded by an addendum update, not assumed here |

Integration rules that bind these rows:

- Each app is wired at the level it can honestly hold today: a live
  surface gets a route, a stopped or ungranted surface gets a labeled
  capsule and its named next step. The full-capability rule invokes
  every capability; it does not promote a blocked surface to a live
  label to look complete.
- None of these rows adds a Console feed. Producer-side reads on the
  snapshot cadence are the only data path, as everywhere else in this
  spec family.
- Hermes is the one integration with an INTERNAL surface in the MVP,
  because its surfaces (chat, presence) already live in the Console.
  The other three are status-and-route rows until their own builds
  say otherwise.

## 5. Open questions for M3ta's resolve step (added by this addendum)

1. Ticker cadence: the ticker inherits the snapshot cadence (parent
   Open question 3). If that cadence lands slow (for example a daily
   producer), does M3ta want a second, ticker-and-social-only
   producer on a faster cadence, or is one producer for the whole
   `DashboardState` the rule?
2. Social producer scope: the first social snapshot run reads
   Instagram, Facebook, and Threads through the connectors on the
   producer's cadence. Which accounts are the hero accounts for the
   first build: the core @th3_m3taway plus which lane handles?
3. A.D.A.M. level display: the A.D.A.M. tab shows the four A.D.A.M.
   autonomy levels and the action-card L0 to L4 as separate
   vocabularies. Does M3ta want a stated mapping between them
   recorded as a ruling, or do they stay separate by design?

These join, and do not replace, the parent spec's four open questions
and addendum 1's two. Suggested order at the resolve step: parent
questions first (they gate the build), then addendum 1's, then these.

## MVP vs later (this addendum's slice)

MVP with the parent build: the tab bar with the QB tab carrying the
parent seven panels unchanged; the Hermes, Meta OS, and A.D.A.M. tabs
as specced (snapshot blocks and live blocks labeled, designed blocks
shown as designed); the ticker with its contract, inventory, and
Reduce Motion replacement; the social panel with its contract and
the three connected-platform snapshot blocks (TikTok and Postiz
blocks rendered with their blockers named); the four Section 4 rows
in Panel 4.

Later, each gated as named: tab persistence across launches; speech
(Hermes tab's designed half, its own spec per the parent); per-agent
A.D.A.M. detail (needs a real feed); the Postiz scheduled block
(unblocks on M3ta's Channels clicks and API key drop, no code change
here); any TikTok analytics block (needs a route that does not exist
yet); OpenClaw click behavior (needs M3ta's ruling); OpenDots route
recording (after bring-up).

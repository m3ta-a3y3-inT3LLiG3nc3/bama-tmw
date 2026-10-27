# M3ta-OS console

The local host surface for M3ta-OS on the Mac: mesh status, Pluto status, Ruth Local pairing, and approval-gated task dispatch to Pluto, in one native window. Replaces: the hirepluto.ai Manage pages for daily status, and the written MVP status map for a quick "what is live" answer. Taken from the M3ta-OS MVP status map (2026-10-22) and the Pluto mesh blueprint and inventory (2026-10-26). Working title: the product name is M3ta's call.

State of the build, 2026-10-26: no app is scaffolded yet. This spec and its fixture are the first intel merged into the bama-tmw fork for this app. The pipeline starts here: copy the Brief into docs/BRIEF.md and the Stories into docs/STORIES.md, then run new-mac-app and improve-loop.

## Brief

```markdown
# M3ta-OS Console (working title)

A native Mac app that shows the state of the M3ta-OS mesh and the hosted Pluto
agent, pairs Ruth Local, and sends approval-gated tasks to Pluto, for M3ta.

## Replaces
hirepluto.ai Manage pages for daily status, the MVP status map for a quick
"what is live" answer, and hand-sent task emails to Pluto.

## Main jobs
1. Show Pluto status: instance live, iMessage paired, connected apps,
   Notion held, credits left.
2. Walk the Ruth Local pairing: installer present, app launched, Connect
   in its 10-minute window, permission states.
3. Send a bounded task to Pluto (inbox or Trigger) after an approval tap,
   and show the reply when it lands.
4. Show mesh status: the five layers, the 11 modules, and the Flagship 5
   from the MVP status map, with the age of the snapshot on screen.

## Data
- MeshState: instance id, plan, credits, channel states, app list, pairing
  state, permission states, plus mesh layers, modules, and flagships.
  Local JSON, refreshed by hand in version one. Seed fixture:
  specs/fixtures/mesh-state-2026-10-26.json in this repo.
- TaskEnvelope: title, body, wire (inbox or trigger), approval state,
  sent at, reply text, replied at. SwiftData or local JSON.
- No secrets stored. No tokens, no keys, no codes, ever.

## Shape
One main window plus Settings, macOS 26 or later. Dock icon on (it is a
console, not a menu-bar utility). Local data. Works offline for viewing.
No accounts of its own.

## System hooks
Launch at login (optional), URLSession, Finder hand-off to the Drive
installer file, System Settings deep links for the two permission panes.

## Reference
Pluto Manage pages (Connections, Computer, iMessage), the 2026-10-22
MVP status map.

## Look
Native, system accent color, one design system per the BAMA design skills.

## Not in version one
- Live polling of Pluto (no API exists; state is manual-refresh)
- Notion connection or page curation inside the app (stays in Pluto/Notion)
- Vault browsing or Pluto vault reach (later milestone, after pairing test)
- CopilotKit or Ko3mand surfaces
- Storing or displaying any credential
```

## How it works

| Part | API / route | Permission |
| --- | --- | --- |
| Pluto status display | Local `MeshState` JSON, edited and refreshed by hand in v1 (Pluto exposes no API, no external MCP, no embed; verified 2026-10-26) | None |
| Mesh status display | The same `MeshState` JSON: layers, modules, flagships from the 2026-10-22 status map, refreshed when a new map lands | None |
| Task dispatch, inbox wire | QB-side send to `ruth-th3-m3ta-way-62da@goshenemail.com`; the app records the envelope and the approval | M3ta approval tap per task (v1) |
| Task dispatch, trigger wire | POST to a Pluto Trigger URL (Triggers are created by asking Pluto in chat; none exist yet) | M3ta approval tap per task (v1) |
| Pairing walk-through | Finder hand-off to `Ruth-Local.dmg` (in M3ta's Google Drive, file id `1_idbdtV6xpYxmZF_u9db7XXIMAX2QJ3e`); then Pluto's own Connect flow in the browser/app | Accessibility + Screen Recording are granted to **Ruth Local** in System Settings, by M3ta |
| Permission state rows | `AXIsProcessTrusted()` pattern applies to this app only if it ever needs Accessibility itself; Ruth Local's grant state is shown as reported by M3ta/Pluto, not read directly | None in v1 |
| Launch at login | `SMAppService.mainApp.register()` | User approves once |

Main types:

- `MeshState`: Codable snapshot: instance, plan, credits, channels (iMessage), apps (name, account, state), notionHeld flag, pairing (installerStaged, appLaunched, paired, permissionsReported), mesh (layers, modules, flagships), capturedAt, source.
- `PairingStep`: enum of `installerStaged`, `installed`, `launched`, `connectWindowOpen`, `paired`, `permissionsGranted`. The UI shows the first incomplete step as the next action.
- `TaskEnvelope`: one outbound task: wire, title, body, approval state, timestamps, reply.
- `DispatchService`: builds the send for the chosen wire; in v1 the inbox send is handed to QB (the Muse runtime) and the app records the result. No send happens without the approval state set.
- `StatusRefresher`: manual refresh in v1; re-reads the local JSON. A future reader may parse exported Pluto state, if Pluto ever offers one (unknown).

Behaviors that matter:

- **No overclaiming.** A state the app has not verified shows as "reported" or "untested", never as live. The pairing's file-reach depth is untested until the one-note vault read test passes.
- **Snapshot age is on screen.** The status pages show the fixture's capturedAt and source. Stale intel must read as stale.
- **The 10-minute window is real.** The pairing view warns before M3ta takes the Connect click and counts the window once open. A lapsed window restarts the step, it does not fail the pairing.
- **Notion stays held.** The apps list shows Notion as "held for page curation" with no connect button in v1. The curation happens in Notion's own share screen, by M3ta.
- **Replies are ground truth on the phone.** iMessage state copy says the phone thread is ground truth; the app never treats a web log as proof of a reply.

## Stories

```markdown
## M1 Status and pairing

### S-001 Show Pluto status from local state
As M3ta, I open the app and see whether Pluto is live, what is connected,
and what is held, without opening a browser.
Acceptance:
- [unit] A fixture MeshState with 6 connected apps and notionHeld = true
  renders 6 app rows and a Held row for Notion.
- [snap] The status page in light and dark mode matches the fixture:
  instance id th3-m3ta-way-62da, plan FREE, iMessage "Paired".
- [manual] Editing the local JSON and pressing Refresh changes the page
  without a restart.
Status: todo

### S-002 Walk the Ruth Local pairing steps
As M3ta, I follow the pairing page step by step until Ruth Local is paired.
Depends: S-001
Acceptance:
- [snap] With pairing state at installerStaged, the page shows one next
  action: "Open the Drive installer", and the later steps greyed in order.
- [manual] The Drive hand-off opens the Ruth-Local.dmg file in Finder.
- [manual] After M3ta reports install + launch, the page advances to the
  Connect step and shows the 10-minute warning before the click.
Status: todo

### S-003 Record the pairing result honestly
As M3ta, after the Connect flow and my permission grants, I mark the
pairing done in the app, with the vault reach shown as untested.
Depends: S-002
Acceptance:
- [unit] Setting paired = true without a vaultTest result keeps the vault
  row at "Untested".
- [snap] The status page shows Pairing "Paired" and Vault reach "Untested"
  as two separate rows.
Status: todo

### S-006 Show mesh status from the same state file
As M3ta, I open the mesh page and see the five layers, the 11 modules, and
the Flagship 5 with the status each one holds in the 2026-10-22 map, plus
how old the snapshot is.
Depends: S-001
Acceptance:
- [unit] The fixture's 5 layers render 5 sections; the modules list renders
  11 rows; the flagships render 5 rows.
- [snap] The mesh page shows A.D.A.M. as "NOT BUILT", Bezalel as "LIVE",
  and the capturedAt date from the fixture in light and dark mode.
- [manual] A status string the app does not know renders as the raw string,
  never as a guessed color or label.
Status: todo

## M2 Dispatch

### S-004 Send a bounded task to Pluto by inbox, approval-gated
As M3ta, I write a task, approve it, and the app records it as sent to
Pluto's inbox.
Depends: S-001
Acceptance:
- [unit] A TaskEnvelope cannot reach state Sent while approval is unset.
- [manual] Approving a test task produces one email to
  ruth-th3-m3ta-way-62da@goshenemail.com, sent by QB, and the envelope
  shows Sent with a timestamp.
- [manual] Pluto's reply, pasted or forwarded back, attaches to the
  envelope as the reply text with its own timestamp.
Status: todo

### S-005 Fire a Trigger once one exists
As M3ta, after a Trigger URL exists in Pluto, I fire it from the app and
see the wake recorded.
Depends: S-004
Acceptance:
- [unit] With no trigger configured, the Trigger wire option is disabled
  with one line: "No Trigger yet. Ask Pluto in chat to create one."
- [manual] Firing the configured Trigger records a Woke entry; a failed
  POST shows the error and keeps the envelope unsent.
Status: todo

## M3 Dropped for v1
- Live Pluto polling or sync (no API exists)
- In-app Notion curation
- Vault browser and Pluto vault reach (returns after the pairing read test)
```

## Gotchas

- Pluto's dashboard health line said "Everything's working" while its own test-text button failed with a router error (2026-10-26). Never render a Pluto state as verified from a dashboard label alone; the phone thread and a real round-trip are the proof.
- The pairing link is single-use with a 10-minute expiry. Any UI that opens the Connect step early burns the window. Gate it behind "app launched" confirmation.
- Pluto's internal name for the instance's agent is "Ruth" (inbox prefix, installer name). Use "Ruth Local" for the desktop app and "Th3 M3ta Way" for the instance, and do not merge the two labels.
- The status JSON is a snapshot, and the UI must show its age. The 2026-10-22 map already went stale on one point within four days: it recorded the Mac as UNREACHABLE, and the relay came back on 2026-10-26. Expect more drift; never hardcode a status in Swift.
- Notion's share screen pre-checks every page, including "Key Vault Index." Any future in-app Notion surface must default to nothing shared, and the curation stays M3ta's.
- Credits are a real constraint: FREE plan, $2.22 left at inventory, refill 2026-11-09. Dispatch stories show the balance they were checked against, so a drained balance never reads as a dispatch failure.
- Osaurus is a separate component (Mac local agent runtime, PARTIAL in the status map). This app does not absorb, host, or replace it. Whether the two converge is undecided.

Done when the app builds and installs from the BAMA pipeline, the status page shows the true 2026-10-26 Pluto state from fixture data in light and dark snapshots, the mesh page shows the 2026-10-22 map statuses with the snapshot date, the pairing walk-through reaches the Connect step in order, and one approval-gated inbox task is recorded sent with its reply attached.

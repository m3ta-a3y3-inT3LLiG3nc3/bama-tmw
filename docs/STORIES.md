# Stories: M3ta-OS Console (working title)

Source: specs/m3ta-os-console.md and specs/bama-buildout-plan-20261026.md.


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

## M1b Copilot

### S-007 Copilot panel through JARVIS runtime
As M3ta, I want a Copilot panel that answers about mesh state through JARVIS's
CopilotKit runtime on 127.0.0.1:9782, using local models first.
Acceptance: panel connects to /api/copilotkit (AG-UI /agui); offline card with
retry when 9782 is down; no keys stored; consequential actions held by JEV.

## M3 Dropped for v1
- Live Pluto polling or sync (no API exists)
- In-app Notion curation
- Vault browser and Pluto vault reach (returns after the pairing read test)


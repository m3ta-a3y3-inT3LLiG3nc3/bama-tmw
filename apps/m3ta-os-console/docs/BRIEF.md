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

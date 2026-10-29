# M3ta-OS lead app

Rollup for the flagship native Mac app in this fork: M3ta-OS Console. It folds in the 2026-10-26 BAMA buildout plan, the 2026-10-27 CopilotKit-in-v1 approval, and a local contact-card surface. Sibling app: [m3ta-tasks.md](m3ta-tasks.md). Implementation detail: [m3ta-os-console.md](m3ta-os-console.md).

State of the build, 2026-10-29: ConsoleCore M3 is the console tree being merged onto main (Home, approvals, health, JARVIS loopback). The `new-mac-app` template sources were dropped from `apps/m3ta-os-console` so the two trees do not mix. CopilotKit in v1 stays JARVIS-only. The Next.js LangGraph starter on `bama-console-m2` stays off main.

## Brief

```markdown
# M3ta-OS lead app (M3ta-OS Console)

A native Mac console that shows mesh and Pluto status, walks Ruth Local
pairing, sends approval-gated tasks, and chats through CopilotKit on the
existing JARVIS runtime, for M3ta.

## Replaces
hirepluto.ai Manage pages for daily status, the written MVP status map,
hand-sent Pluto task emails, and a second CopilotKit runtime in the console.

## Main jobs
1. Show Pluto and mesh status from the local MeshState snapshot.
2. Walk Ruth Local pairing and permission state.
3. Send a bounded task to Pluto after an approval tap.
4. Chat with JARVIS through CopilotKit on 127.0.0.1:9782 only.

## Data
- MeshState JSON. Seed fixture:
  specs/fixtures/mesh-state-2026-10-26.json. No phone numbers or emails
  in the committed fixture; use placeholders.
- TaskEnvelope: title, body, wire, approval, timestamps, reply.
- No secrets stored. No tokens, no keys, no codes, ever.

## Shape
One main window plus Settings, macOS 26 or later. Dock icon on.
Works offline for viewing. Copilot panel shows an offline card when
JARVIS is down.

## System hooks
Launch at login (optional), URLSession to loopback JARVIS and rea-mcp,
Finder hand-off to the Ruth Local installer, LocalAuthentication for
JEV approvals (M3).

## Reference
Pluto Manage pages, MVP status map 2026-10-22, JARVIS CopilotRuntime
on 127.0.0.1:9782, BAMA buildout plan 2026-10-26.

## Look
Native, one BAMA design system.

## Copilot (in version one, approved 2026-10-27)
- CopilotKit chat panel talks to JARVIS only:
  http://127.0.0.1:9782/api/copilotkit and AG-UI at /agui.
  No second runtime in the Mac app.
- Local models first (Ollama on 127.0.0.1:11434), $0.
- Actions that send, spend, or delete go through the JEV approval gate.
- If JARVIS is down, show an offline card; the rest of the console still works.

## Not in version one
- Live polling of Pluto
- Notion curation inside the app
- Vault browsing
- Ko3mand surfaces
- Lead-signals buyer lists (skill, not this app)
- Editing the ConnectMachine card at mycm.ai (separate signed-in publish)
- Storing or displaying any credential
```

## How it works

| Part | API / route | Permission |
| --- | --- | --- |
| Status display | Local MeshState JSON | None |
| JARVIS health | GET http://127.0.0.1:9782/health and 9783 health | None |
| CopilotKit | JARVIS `/api/copilotkit` and `/agui` | None in v1; JEV for send/spend/delete actions |
| Task dispatch | Approval tap, then QB-side send. Inbox address stays in the console spec, not in the fixture | M3ta approval tap per task |
| Pairing | Finder hand-off to Ruth-Local.dmg | Accessibility and Screen Recording granted to Ruth Local by M3ta |
| M3 approvals | JEV pending files plus Touch ID | LocalAuthentication |

Main types stay in [m3ta-os-console.md](m3ta-os-console.md): `MeshState`, `PairingStep`, `TaskEnvelope`, `DispatchService`.

## Stories

Milestone 0, already on main: spec, fixture, README row, `new-mac-app` scaffold.

- [x] Console spec and fixture exist on `origin/main` (PR 1, 2026-10-29).
- [x] Fixture phone and email fields use placeholders before further merge.
- [ ] Kingdom names the product.

Milestone 1 to 3 live on feature branches, not on main:

- [x] Native window reads MeshState from the bundled fixture (M1).
- [x] JARVIS loopback health, models, and offline card (M2).
- [x] Approval inbox, Touch ID, GET-only loopback backend on 127.0.0.1:9791 (M3). Code is in this merge; live Touch ID still needs a Mac run.

Milestone 4 to 8 still open:

- [ ] One design system pass on the implementation that lands on main.
- [ ] CopilotKit panel on JARVIS only. Do not ship the Next.js LangGraph starter in `apps/m3ta-os-console` as the v1 copilot; that is a second runtime.
- [ ] OpenBot / OpenDots / OpenMuse webviews with offline cards (M6).
- [ ] Desktop wrappers stay loopback only (M7).
- [ ] Tests, loopback scan, JEV holds sends; local commit, then a PR (M8).

Contact card (local, not the Mac app):

- [x] Public ConnectMachine card at https://mycm.ai/a/Fum3a shows name, title, org, work email, mobile.
- [ ] Local `.vcf` and HTML card in the planner workspace, emails only when present on the public card.
- [ ] ConnectMachine dashboard edit is a signed-in publish. It is not this PR.

## Gotchas

- `origin/main` console is the BAMA `new-mac-app` template. Feature branches replaced that tree with ConsoleCore. Merging a feature branch onto main is a product pick, not a fast-forward.
- The committed fixture must not contain a phone number or email. Instance id and GitHub/Slack account names may stay.
- CopilotKit v1 is JARVIS on 9782. A CopilotKit MCP URL that 404s is not a runtime.
- Lead-signals is a treg skill. It is not a BAMA spec and it is not v1 of this app.
- `m3ta-tasks` is a sibling personal to-do app, not this lead app.
- Nothing in this spec authorizes a push to `main` without a PR tap.

## Done when

The redacted fixture is on the branch that targets `origin/main`, this rollup spec is listed in `specs/README.md`, and the console spec records CopilotKit in v1. Shipping M1 to M8 is later PRs, one implementation tree at a time.

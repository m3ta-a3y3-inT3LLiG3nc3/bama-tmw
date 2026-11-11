# M3ta-OS Console

Native Mac app (Swift, macOS 26+) that shows the state of the M3ta-OS mesh
and the hosted Pluto agent, walks the Ruth Local pairing, and records
approval-gated task dispatch. Spec: `specs/m3ta-os-console.md` in this repo;
brief and stories: `docs/BRIEF.md`, `docs/STORIES.md`.

## Copilot design (S-007, approved 2026-10-27)

The Copilot panel is a **client of JARVIS's existing CopilotKit runtime
only**:

- Chat runs are POSTed as AG-UI runs to the CopilotKit runtime's agent
  route, `http://127.0.0.1:9782/api/copilotkit/agent/default/run`, and the
  streamed events are folded into the chat. (The top-level `/agui` route on
  the same port is JARVIS's own REA skill dispatcher, not the chat agent.)
- **No second agent.** The Mac app starts nothing: no embedded LangGraph
  agent and no channel host. The stock `copilotkit init` scaffold was
  removed for that reason (git history at 58da1c9). The auth route below is
  a handler, not that scaffold.
- Local models first is JARVIS's routing job (Ollama on 127.0.0.1:11434);
  the Models card shows the live route from `GET /api/models`.
- No cloud keys in the app. No secrets are stored, ever.
- Copilot actions that send, spend, or delete are executed inside JARVIS
  and held by the JEV approval gate; the panel only displays tool activity.
- If JARVIS is down, the Copilot screen shows an offline card with Retry;
  the rest of the console (status, pairing, mesh, bots, brain) still works
  from the local snapshot.

## Copilot auth boundary

`src/app/api/copilotkit/[[...slug]]/route.ts` is a CopilotKit 1.79 route for
this app. It calls `identifyUser` from the signed-in session and refuses
another caller's thread on read, run, replay, and subscribe. Login and the
runtime share one registry on `globalThis`, because Next can bundle those
routes apart. Logout aborts in-flight and not-yet-dispatched agent work.
Browser sockets are not blanket-blocked: `/api/copilotkit/socket` accepts a
session and forwards the runtime's AG-UI stream.

This is not a second LangGraph agent and it stores no cloud keys. The Mac
panel still posts to JARVIS on loopback. That direct ingress is outside this
boundary.

Implementation: `Sources/ConsoleCore/CopilotClient.swift` (AG-UI client,
event parser, run accumulator), `Sources/ConsoleCore/JarvisClient.swift`
and `CopilotHealth.swift` (read-only loopback probes),
`Sources/M3taOSConsole/CopilotPanel.swift` (chat UI + runtime status).

## Build

```bash
swift build            # debug build
swift test             # ConsoleCore unit tests
./scripts/package.sh   # release build -> dist/M3taOSConsole.app (ad-hoc signed)
npm test               # Copilot auth boundary
```

Ports for the JARVIS endpoints are configurable in Settings (host is
always 127.0.0.1; defaults 9782 agent-runtime, 9783 rea-mcp).

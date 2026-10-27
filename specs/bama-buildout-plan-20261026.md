# BAMA buildout plan (2026-10-26) - plan only, awaiting Kingdom's go

## Status today
- bama-tmw: 2 commits on main (BAMA 1.0.0 + plugin icon). Skills/specs scaffold only; no app code.
- specs/m3ta-os-console.md: Brief written, "no app is scaffolded yet". Uncommitted (with specs/fixtures, README edit). v1 excludes CopilotKit/Ko3mand.
- JARVIS (m3ta-os-mvp-m2/apps/jarvis-hud, Tauri, owner K0Ad33) already runs CopilotRuntime /api/copilotkit + AG-UI /agui on 127.0.0.1:9782.
- OpenBot: Electron desktop (OpenBot.app 0.51.1) running, web app :3010. OpenDots: Vite web on :5174, no desktop build. OpenMuse (~/openmuse): server/worker/mobile-web, no desktop build, deps not installed.

## Milestones
| # | Milestone | Owner | Est. |
|---|-----------|-------|------|
| M0 | Commit console spec + fixtures; docs/BRIEF.md + STORIES.md; Kingdom names product, approves amending v1 to include CopilotKit | Hermeez + Kingdom | 20 min |
| M1 | Scaffold native console (new-mac-app skill): SwiftUI window, MeshState from fixture, Settings | K0Ad33 | 2-3 h |
| M2 | Wire JARVIS: console reads JARVIS health (9782/9783) + REST /api/rea; JARVIS gets a "Bama console" deep link | K0Ad33 | 2 h |
| M3 | Backend rebuild: one local service (127.0.0.1) exposing MeshState, TaskEnvelope store, approval gate via JEV (Touch ID) | K0Ad33 | 3-4 h |
| M4 | Frontend UI/UX rebuild: BAMA design skills, one design system, offline states, Waypoint tab parity | K0Ad33 | 3-4 h |
| M5 | CopilotKit: console talks to JARVIS's CopilotRuntime (single runtime, no second one); Ollama-first, $0 | K0Ad33 | 2 h |
| M6 | OpenBot/OpenDots/OpenMuse: embed as webviews with offline cards; register their agents as shared AG-UI agents behind JARVIS /agui; route models via local Ollama | K0Ad33 + Hermeez | 4-6 h |
| M7 | Desktop wrappers: Tauri shell for OpenDots and OpenMuse (loopback only), LaunchAgents optional | Hermeez | 2-3 h |
| M8 | Verify: tests, build, loopback scan, JEV holds sends; local commit, no push | Hermeez | 1 h |

Total ~20-26 h. Every milestone >30 min needs Kingdom's go.

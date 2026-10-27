# M3ta-OS Console: free local stack

How the Console (`specs/m3ta-os-console.md`) talks to a zero-cost, local-first stack. No Swift app is scaffolded here; this is wiring only. Sample config: `config/m3ta-os-local.example.toml`.

| Service | Endpoint | Access | Notes |
|---|---|---|---|
| Ollama | `http://127.0.0.1:11434/v1` | read/write (local) | chat `m3ta/qwen3-abl-8b-nothink-32k`, vision `qwen2.5vl:7b`, embeddings `nomic-embed-text` |
| Jev UltraFast | local process | approval-gated | `JEV_BACKEND=openai` points the decision heads at Ollama (jev-ultrafast PR #1); websites with no connector only |
| n8n | `http://127.0.0.1:5678` | approval-gated | API key in Keychain |
| Obsidian vault | file path | read-only | never written by the Console |
| Orbit | connector/API | read-only | token in Keychain |
| OpenBot | local web view | view | CopilotKit fork |

## Rules
- **Approval tap:** every dispatch, send, workflow run, or browser action needs an explicit tap in the Console.
- **Keychain:** secrets are stored only in the macOS Keychain; config files hold item names, never values.
- **Local only:** the Console warns when any endpoint is outside loopback or Tailscale.
- **Tailscale:** Ollama may be exposed to M3ta's other machines over Tailscale only (bind to the tailnet IP, not 0.0.0.0 on public interfaces).

## Hardware
Host Mac: 48 GB RAM. 7–8B models run comfortably; larger ones (up to ~30B quantized) are possible but not default.

## Status
Config and docs only. Models, n8n and Jev on the Mac are not installed by this change.

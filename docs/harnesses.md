# Agent harnesses behind the M3ta-OS skills server

The Console does not run harnesses itself. Each harness is exposed as a skill behind the m3ta-os-mvp skills server (`127.0.0.1:9783`, helper `:9782`), which K0Ad33 owns (branch `agent/k0ad33/mac-app-m1`, plus an Ollama+Jev gate branch). This repo documents the contract only and does not edit that backend. Config: `config/harnesses.example.toml`.

Default model plane: local Ollama at `http://127.0.0.1:11434/v1` (OpenAI-compatible). On the 48 GB Mac: `qwen2.5-coder:7b` for code, `deepseek-r1:14b` for reasoning, `m3ta/qwen3-abl-8b-nothink-32k` for the Jev gate. Every run needs an approval tap. Keys, where needed, live in the Keychain only.

| Harness | Source (fork) | Local Ollama | Paid key | Verified |
|---|---|---|---|---|
| Jev UltraFast | jev-ultrafast | yes, `JEV_BACKEND=openai` | no | yes (PR #1) |
| Pi coding agent | badlogic/pi-mono (no fork) | yes, `models.json` / `ollama launch pi` | no | yes (pi.dev, docs.ollama.com) |
| DeepSeek Harness | deepseek-harness-tmw ← deepseek-ai/deepseek-harness | unverified | likely DeepSeek API | repo exists; usage unverified |
| DeepSeek Reasonix | DeepSeek-Reasonix-tmw ← esengine/DeepSeek-Reasonix | unverified | likely DeepSeek API | repo exists |
| Gemini CLI | gemini-cli ← google-gemini/gemini-cli | no | free tier or key | repo exists |
| Google ADK | none found | via LiteLLM (unverified) | no | unverified |
| Aider | aider-tmw ← Aider-AI/aider | yes, `ollama_chat/...` | no | repo exists |
| browser-use | browser-use ← browser-use/browser-use | yes | no | repo exists |
| OpenClaw | openclaw-tmw ← openclaw/openclaw | unverified | depends | repo exists |
| Hermes Agent | hermes-agent-TMW ← NousResearch/hermes-agent | unverified | depends | repo exists |
| GitHub Copilot CLI | copilot-cli-tmw ← github/copilot-cli | no | subscription | repo exists |
| Claude Code | claude-plugins-official, claude-mem | no | yes | — |
| Codex CLI | skills-codex-tmw | `--oss` (unverified) | optional | — |
| Orgo | cloud desktops | no | yes | — |

Free, fully local now: Jev (after PR #1), Pi, Aider, browser-use. Everything marked unverified needs a check against the repo README before it is wired.

# BAMA

Agent skills for building native macOS apps. Installed as a Claude Code and
Codex plugin from `.claude-plugin/`, or through `npx skills add`.
`AGENTS.md` at the root is a copy of this file (`.claude/CLAUDE.md`);
keep them identical.

## Layout

- `skills/<stage>/<name>/SKILL.md`, stages in pipeline order: `start`, `plan`,
  `code`, `design`, `ship`.
- References sit next to `SKILL.md` (`recipes.md`, `patterns.md`) and are
  linked relatively. Scripts go in `scripts/`, templates in `template/`.
- `agents/openai.yaml` in every skill: Codex display name and short
  description. A user-invoked skill also sets
  `policy.allow_implicit_invocation: false`.
- `.claude-plugin/plugin.json` lists every shipped skill in `skills`.
- `specs/<app>.md`: build plans for small apps, taken from Onyx. Each has
  Brief, How it works, Stories, Gotchas, and a "Done when" line, in that
  order. `specs/README.md` lists them.

## Writing skills

Follow Matt Pocock's `writing-for-agents` rules:

- The description is a **context pointer**: one short sentence on what it
  is, then "Use when" and one trigger per branch. Front-load the leading
  word.
- Inline what every branch needs. Push what only some branches need into a
  sibling file behind a link.
- Every step ends on a checkable condition. Every skill ends with a
  "Done when" line.
- Prompt the positive. Use a prohibition only as a hard guardrail, next to
  the positive target.
- Cache only what the environment cannot tell the agent: conventions,
  reasons, gotchas from real apps.
- One skill calls another with "Call the Skill tool with `<name>`".
- No em dashes. Plain words, short sentences, active voice.

## Adding a skill

1. Create `skills/<stage>/<name>/SKILL.md` and `agents/openai.yaml`.
2. Add it to `plugin.json` `skills`, the README table, and the router
   (`skills/start/bama/SKILL.md`).
3. Run `claude plugin validate . --strict`.
4. Keep `version` in `plugin.json` at 1.0.0 until the first release. After that, bump it, so installed copies update.

## Best-Configuration Rule (M3ta, 2026-11-01)

Every standing build/configuration rule is a DEFAULT, not a hard constraint. When a different configuration, tool, model, runtime, or architecture better serves the outcome — features, integration, autonomy, performance, scalability — use it, note the deviation in one line, and move on; no deviation needs advance justification. Local-first model routing, default build grids/stacks, one-tool-per-category, single-runtime guidance, and fold-in/clones rules are starting points, never blockers. NOT configuration rules (unchanged): platform safeguards, secret handling, approval gates for consequential external actions (sends, publishes, purchases, deletions), never auto-post, and the confirmed-only protocol for business terms/fees.

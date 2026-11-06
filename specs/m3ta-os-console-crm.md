# M3ta-OS Console CRM module

The native CRM face inside the M3ta-OS Console: the M3ta-CRM roster, follow-ups due, retention alerts, and open tasks, read live from the CRM's machine API, with create-contact and create-task as the human-in-the-loop writes. Replaces: opening the M3ta-CRM web app (localhost:3120) for a daily CRM check. Taken from the CRM repo's BAMA registration stub (`nova-ai-crm/docs/bama/m3ta-crm.bama.md`) and its integration contract (`nova-ai-crm/docs/INTEGRATIONS.md`, `integration.manifest.json`), both verified 2026-11-06.

State of the build, 2026-11-06: the CRM web app and its machine API are built and live (`/api/v1/*` on localhost:3120, bearer token auth, `x-agent-id` attribution). The native shell slot exists as the registration stub only. This spec is the module build: ConsoleCore client + state, one dashboard tab, tests.

Deviation from the registration stub, recorded 2026-11-06: the stub registered a `web-app-wrapper` shell for a standalone `m3ta-crm` app; M3ta's build order supersedes it — the native face is a module inside the M3ta-OS Console. This build updates `nova-ai-crm/docs/bama/m3ta-crm.bama.md` to match (status + file map) in the same pass.

## Brief

```markdown
# M3ta-OS Console CRM module

A native CRM tab inside the M3ta-OS Console that shows the M3ta-CRM
roster, follow-ups due, retention alerts, and open tasks, and creates
contacts and tasks, for M3ta.

## Replaces
Opening the CRM web app for the daily check: who is in the roster,
what follow-up is due, who is going cold, what tasks are open.

## Main jobs
1. Show the roster: every company (workspace) with its contact, deal,
   task, and snapshot counts (the counts arrive in the payload; the
   slug is the cross-system join key, not a client-side join).
2. Show follow-ups due: open follow_up and retention tasks whose due
   date has passed, oldest first, with contact and company names.
3. Show retention alerts: active contacts gone cold past the retention
   window (14 days unless the server says otherwise), with last
   activity.
4. Show open tasks and the pipeline summary (open/won/lost deals,
   pipeline value, counts by stage).
5. Create a contact and create a task from the tab. The operator's
   form and confirm tap are the human-in-the-loop step; nothing writes
   any other way.

## Data
- All data comes from the M3ta-CRM machine API at /api/v1/*. The
  snapshot (CRMSnapshot) holds exactly five reads: summary, companies,
  followups, retention, tasks. The contacts read is on-demand only
  (the client's search method); it is not in the snapshot and has no
  panel in this milestone. Payload shapes are the CRM's Prisma rows
  as serialized by its route handlers (see How it works). The Console
  stores no CRM data of its own; it renders what the API answered,
  with the checked-at time.
- Nullability is per field, from the handlers: every field the API
  can return as null is optional in the models (task dueAt and link
  ids, contact email/phone/companyId/lastActivityAt, and the rest).
  One required-but-null field must never fail a whole panel.
- Config precedence, one rule: environment (CRM_BASE_URL) over the
  Settings base-URL override (crmBaseURL) over the default
  http://localhost:3120; the client normalises a trailing slash on
  the base. Agent id: CRM_AGENT_ID over the default
  "m3ta-os-console". The bearer token comes from the CRM_API_TOKEN
  environment variable only. It is never written to UserDefaults, a
  plist, a fixture, or this repo.
- The token is a FULL-SCOPE credential: it authorizes every
  /api/v1/* route on the server, including sync and snapshots,
  whatever this module calls. The module sends it only to a loopback
  base URL or an HTTPS one; a plain-http non-loopback base leaves
  the module unbound with that reason on its face.
- Token unset means the module is UNBOUND: the tab shows the unbound
  screen with the fix on its face. Unbound is a state, never a silent
  empty roster. Injection route for the packaged app: launch it with
  the token in its environment (the build notes' run sheet uses
  `open --env`); a Finder double-click inherits no shell environment,
  and the unbound screen says so.

## Shape
One more tab ("CRM") in the existing dashboard tab bar, after A.D.A.M.
Panels in the existing design system (system 1: gold #C9A227 on deep
black, DashboardTokens, DashboardPanel frames). Read triggers are
exactly three: the tab appearing (then its own loop on the
dashboard's refresh interval while shown), the console Refresh
action, and a completed write. The CRM is NOT added to the
dashboard's every-10-seconds probe loop for the other tabs. Writes
are one-shot, operator-tapped.

## System hooks
URLSession only. No new permissions, no keychain in this milestone,
no background work of its own.

## Reference
The CRM web dashboard (same numbers, same service layer), the
JarvisClient read pattern (Probe, 200-only, decode-or-offline), the
DashboardStore snapshot discipline (an error shows; nothing stale is
substituted silently).

## Look
Native, system 1 dashboard tokens, one design system. Status words
render raw outside the DashboardStatus vocabulary.

## Not in this milestone
- Editing or deleting anything (the machine API offers no delete;
  the tab invents none).
- Deals pipeline board, snapshots, bookings, email (the web app and
  the AG-UI panel keep those).
- Orbit sync controls (the CRM's npm lanes own sync; the tab reads).
- Storing the token anywhere, or a token entry field in Settings.
- iOS companion CRM screen (ConsoleCore is shared, so it can follow;
  the macOS tab is this milestone).
```

## How it works

| Part | API / route | Permission |
| --- | --- | --- |
| Pipeline summary | GET /api/v1/summary | Bearer token (env), read |
| Roster | GET /api/v1/companies (rows carry `_count`: contacts, deals, tasks, snapshots) | Bearer token (env), read |
| Contacts (search/list) | GET /api/v1/contacts?q= (latest 100 without q; with q: searchContacts caps at 25, sorted by fullName) | Bearer token (env), read |
| Follow-ups due | GET /api/v1/followups (open follow_up/retention tasks due at or before now, dueAt ascending, contact/deal/company included) | Bearer token (env), read |
| Retention alerts | GET /api/v1/retention (client omits `days`; the server default RETENTION_DAYS wins; answers `{days, cutoff, cold: [contacts]}`, cold ordered by updatedAt as returned) | Bearer token (env), read |
| Open tasks | GET /api/v1/tasks (open tasks, contact/deal/company/assignee included) | Bearer token (env), read |
| Create contact (HITL) | POST /api/v1/contacts `{fullName, email?, phone?, companyName?}` | Operator fills the form and taps confirm; `x-agent-id` attributes the write |
| Create task (HITL) | POST /api/v1/tasks `{title, kind?, dueAt?, contactId?, companyId?, dealId?}` | Operator fills the form and taps confirm; `x-agent-id` attributes the write |
| Auth failure shape | 401 without/with a wrong token; 503 when the server's own CRM_API_TOKEN is unset (lane disabled) | Rendered as offline with the HTTP code and the lane state in words, never as an empty roster |
| Server failure shape | Only the two 400 validations return `{error: ...}` JSON. An invalid dueAt or an unknown contact/company/deal id throws unhandled server-side (500, body not JSON) | Client rule, no exceptions: any non-200 (reads) or non-200/201 (writes) is offline with the HTTP code; the server's error text is shown only when a JSON `error` field is actually present. The client never assumes a body shape |

Main types (ConsoleCore):

- `CRMConfig`: baseURL, token (optional), agentId. `isBound` requires a non-empty token AND a loopback-or-HTTPS base; `bindProblem` names the failing half in words. Resolution and precedence per the Brief's Data section.
- `CRMSummary`: every field is a scalar (openDeals, pipelineValue, wonDeals, wonValue, lostDeals are deal counts/values; contacts and companies are integer counts, not collections) except byStage: stage name to {count, value}. Mirrors `getSalesSummary`. The panel displays all six totals.
- `CRMCompany`: id (the model identity, Identifiable), name, slug (the cross-system join key for Orbit/Paperclip/matrix joins, not row identity; nothing joins client-side, the counts arrive in the payload), type, status, website, notes, source, ISO date strings, and `counts` decoded from the `_count` key.
- `CRMContact`: id, fullName, first/last name, email, phone, companyName, companyId, nested company, status, lifecycleStage, engagementScore, isStarred, lastActivityAt, source, ISO date strings. Includes vary per route and every nested field is optional: no include without q, company + tags with q, company only in retention, neither inside a task row. The `tags` wrapper is explicitly ignored (no panel uses it). POST answers are the bare row with no includes at all.
- `CRMTask`: id, title, description, status, priority, kind, dueAt, contactId/companyId/dealId, and the included contact, company, deal, and assignee. The routes send these as FULL Prisma objects; the client decodes a subset (deal: id/title/value/status; assignee: id/name) and holds nothing more. One type serves followups and tasks; both routes return task rows. POST /tasks answers the bare created row at 200, no includes; the same model decodes it because every include is optional.
- `CRMRetention`: days, cutoff, cold contacts.
- `CRMClient`: async reads and the two writes over URLSession, following the JarvisClient pattern (reads 200, writes 200/201, else offline-with-reason; ephemeral session, no proxy). Header policy, all requests: Authorization bearer + `x-agent-id`; POSTs with a body add Content-Type application/json. Pure body builders and decoders are static so tests cover them without a server.
- `CRMSnapshot`: exactly the five read results (summary, companies, followups, retention, tasks) as `Probe` values plus checkedAt (the moment the refresh completed), with count helpers that return nil (unknown) when a probe is offline, never zero.
- `CRMStore`: the observable store (mirrors DashboardStore): owns the config and the current snapshot, refreshes on the three triggers in the Brief's Shape section.

Behaviors that matter:

- **Unbound is detectable, not silent.** No token in the environment: the tab renders the unbound screen (what is missing, where to set it) and makes no network call. A bound tab whose server is down renders offline panels with the reason and the checked-at time.
- **No overclaiming.** Counts come only from payload fields. A failed read shows its offline reason in its panel; the other panels still render. Nothing is cached across launches as if it were live.
- **Dates stay strings until displayed.** The API serializes Prisma DateTime values as ISO-8601 with fractional seconds; models keep the strings (the MeshState/DashboardState convention) and one parser handles display and overdue checks.
- **Writes are the operator's.** The create forms write only on the confirm tap, attribute with the resolved `x-agent-id` (default `m3ta-os-console`), and show the server's answer (created row or its error text). No write is retried automatically. The server does not dedupe creates and barely validates: a second confirmed tap makes a second row, so the confirm controls disable while a write is in flight, and the form says duplicates are possible.
- **The assignee wart stays server-side.** Task rows include the assignee user object; the client decodes id and name only and never stores or displays any other assignee field.
- **Nothing logs payloads or headers.** No CRM response body and no Authorization header is ever written to a log, a fixture, or an error string; offline reasons carry the HTTP code and, at most, the server's own short `error` field.
- **The server's due filter is authoritative.** The follow-ups panel renders what /followups returned; the client date parser is for display (and due-date emphasis) only and never drops a row the server sent.

## Stories

```markdown
## M-CRM Native module

### CRM-001 Show the unbound state when no token is set
As M3ta, when CRM_API_TOKEN is not in the app's environment, I see a
CRM tab that tells me the module is unbound and how to bind it, not an
empty CRM.
Acceptance:
- [unit] A config with a nil or empty token reports isBound = false,
  and the client's reads return the unbound offline reason without a
  network call. A config with a token but a plain-http non-loopback
  base URL is likewise unbound, with the loopback/HTTPS reason.
- [snap] The CRM tab with an unbound config shows the unbound panel:
  what is missing (CRM_API_TOKEN), the default base URL, and no
  roster-shaped content.
- [manual] Launching the packaged app without the token shows the
  unbound screen; launching with it shows live panels (Mac run sheet).
Status: todo

### CRM-002 Show the roster with counts
As M3ta, I open the CRM tab and see every company with its contact,
deal, task, and snapshot counts.
Depends: CRM-001
Acceptance:
- [unit] A companies fixture with `_count` decodes counts onto the
  company model; a row without `_count` decodes with nil counts.
- [snap] The roster panel lists companies in API order with counts
  where the payload carries them, and the summary panel shows the
  payload's own totals.
- [manual] With the CRM server running, the roster matches the web
  dashboard's company list (Mac run sheet).
Status: todo

### CRM-003 Show follow-ups due and open tasks
As M3ta, I see what follow-up is due or overdue, oldest first, with
the contact and company each task belongs to, plus the full open
task list. The server's due filter is authoritative; the client
never re-filters.
Depends: CRM-002
Acceptance:
- [unit] A followups fixture decodes task rows with nested contact
  and company names; the overdue helper parses fractional-second
  ISO dates and flags a past dueAt.
- [snap] The follow-ups panel shows title, contact, company, and due
  date per row; an empty payload renders "Nothing due", not a blank.
- [manual] A task created in the web app with a past due date appears
  in the tab after refresh (Mac run sheet).
Status: todo

### CRM-004 Show retention alerts
As M3ta, I see which active contacts have gone cold past the
retention window, with their last activity.
Depends: CRM-002
Acceptance:
- [unit] A retention fixture decodes days, cutoff, and the cold list;
  a contact's last activity reads lastActivityAt, falling back to
  updatedAt, matching the server rule.
- [snap] The retention panel shows the window in days from the
  payload (never a hardcoded 14) and one row per cold contact.
Status: todo

### CRM-005 Create a contact, operator-confirmed
As M3ta, I add a contact from the tab; it exists in the CRM with the
Console's agent id on the write.
Depends: CRM-001
Acceptance:
- [unit] The contact body builder encodes fullName and omits nil
  optional fields; an empty fullName never produces a body.
- [manual] Creating "Test Person" from the tab, then searching the
  web app, shows the contact; the server ActivityLog attributes the
  write to the agent id the config resolved to (default
  m3ta-os-console) (Mac run sheet).
- [manual] A server rejection (400) shows its error text in the form;
  nothing is retried silently. The Create button is disabled while
  the write is in flight (the server does not dedupe).
Status: todo

### CRM-006 Create a task, operator-confirmed
As M3ta, I add a task from the tab and see it in the open list after
refresh.
Depends: CRM-005
Acceptance:
- [unit] The task body builder encodes title and kind and an ISO
  dueAt when set, and omits unset links.
- [unit] The kind control is a fixed picker over the server's kind
  values (follow_up, retention, general, appointment); no free text.
- [manual] A task created from the tab appears in the web app's task
  list and in the tab's open tasks after refresh (Mac run sheet).
Status: todo

## M-CRM Dropped for this milestone
- Company snapshots from the tab (POST /companies/:id/snapshots
  exists; the web app keeps it for now)
- Inbound Orbit sync trigger (POST /api/v1/sync/orbit)
- Deals, notes, bookings, email surfaces
```

## Gotchas

- The server's token and the client's token are different failure modes with different faces: server CRM_API_TOKEN unset answers 503 (lane disabled); client token missing means the module never calls (unbound screen); client token wrong answers 401. The UI copy must not merge them.
- Prisma serializes dates with fractional seconds (`2026-11-06T16:45:00.000Z`). The shared SnapshotAge parser (internet date-time, no fractional seconds) returns nil for them; CRM dates need the fractional-seconds parser or every due date reads as unknown.
- Companies carry their rollup counts under the key `_count`, not `counts`. A model that looks for `counts` decodes fine and shows nothing; the fixture test pins the real key.
- Follow-ups and open tasks are the same row shape from two routes (followups filters kind and due date server-side). Do not build two task models.
- Task rows include the assignee as a full user object from Prisma. Decode id and name only; the client never holds the rest.
- The CRM server binds localhost:3120 on the machine it runs on. On the Mac run sheet the server and the app are the same machine only if M3ta runs the CRM there; a VM-hosted server needs the base URL pointed at a reachable address, which is a config change, not a code change.
- The dashboard's on-open read set is named and bounded. The CRM tab reads only when the tab is shown or refreshed; it does not add the CRM to the dashboard's every-10-seconds probe loop for the other tabs.
- Accepted limits, not bugs: companies, tasks, and followups have no server-side pagination; the five-read snapshot is not atomic, so counts can disagree mid-refresh under a concurrent write; byStage arrives in unsorted deal-iteration order (the panel sorts stage names for display).
- Fixture provenance: the unit-test fixtures are authored from the route handlers and the service layer, not captured live (the module had not run when they were written). The Mac run sheet includes capturing sanitised live fixtures per route (GET and POST, including null cases) and diffing them against the test set before the module is called verified.
- Model fields mirror the CRM's Prisma schema (the routes serialize whole rows): fields no panel displays yet (company notes, contact engagementScore/lifecycleStage, task priority/description) are decoded because the row carries them and drop out only if the schema does.

Done when the spec's unit tests pass on the Mac (`swift test`, including the CRM fixture tests), the CRM tab shows the unbound screen without a token and live roster, follow-ups, retention, and tasks with it, one contact and one task created from the tab appear in the web app attributed to m3ta-os-console, and the build notes record what is code, what is scaffold, and the Mac run sheet.

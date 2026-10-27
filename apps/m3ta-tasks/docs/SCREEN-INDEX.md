# Todoist screen index — captured 2026-10-26 (fills the SCREEN INDEX slots in todo-clone-spec-draft-2026-10-26.md)

Source: read-only browser capture of app.todoist.com, account "C0ach", dark theme, narrow left sidebar + wider main pane. Nothing was created, edited, completed, or deleted. Screenshots exist as browser-session captures (i4–i19) plus one PDF of Today; no PNG files were exported — per the clone ruling, web shots are structure evidence, never pixel targets, so this written index is the deliverable.

Account state found during capture: Todoist plan "Beginner" (free), over free limits — My Projects shows USED 83/5, filters 3/3 — and most screens carry a "view-only / exceeded free limits, Upgrade to edit" banner. The clone spec is unaffected (local app, no account limits), but his live Todoist is effectively read-only at this tier.

## Screens

1. **Today** — /app/today. Header "Today", "329 tasks", a duration readout, "Display" view-options. Board columns grouped by label (an Events column, then @active-build, @apple-native, @build, @context-build, @crm, @deck-production…). Cards: circular checkbox, title, description excerpt, date/duration, labels, project; each column ends with "+ Add task".
2. **Inbox** — /app/inbox. Header "Inbox", Display, Comments, project-options menu. Board columns: "Overdue" (83, with a Reschedule control) and "No date" (222). Same card pattern as Today.
3. **Upcoming** — /app/upcoming. Month selector ("October 2026"), Previous week / Today / Next week, week strip with the current day selected. List-style (not board): a long "Overdue" list with Reschedule; rows show checkbox, title, date/time, sub-task count where present, labels, project.
4. **Filters & Labels** — /app/filters-labels. Two collapsible sections: "My Filters USED: 3/3" (🌞Today's Objectives🌞, 🚦Tasks 90 days old🚦 — 1806 tasks, ‼️High priority tasks due today‼️) and "Labels" with "+ Add new label" (m3ta-os 288, imported-omnifocus 242, attio 129, crm 125, Projects 16, FNPC 8, Planning 3, Clients 1…), plus a collapsed "Shared Labels". Rows: tag icon + name + count.
5. **Project view — Podcast Workflow** — /app/project/podcast-workflow-…. Breadcrumb "My Projects / EAGLE EYE VISION LABZ, LLC. / 🎬 Content /", header with Share, Display, Comments, options menu, "This project is view-only" banner. Board sections: Pre-production 📒 (6), Production 🎙 (4), Post-Production 🎧 (5), Distribution 🌎 (3). Cards here are minimal: checkbox + title (one shows "0/4" sub-tasks).
6. **Task detail** — opens as a centered dialog over the dimmed board. Breadcrumb (project / section), Previous (disabled) / Next task, More actions, Close. Body: checkbox, title, empty Description placeholder; right rail: Project, Date, Deadline, Priority (P4), Labels, Reminders, Location — disabled in view-only.
7. **Completed / activity (Reporting)** — /app/activity?eventType=item:completed. Header "Reporting: My completed tasks", dropdown, filter pills (All workspaces, All projects, Everyone, Completed tasks, Any date), disabled Export, Reset filters. Current filter returned the empty state: "No activity".
8. **Settings** — /app/settings/account, a dialog over the app. Left column: Search + tabs (Account, General, Subscription, Theme, Sidebar, Quick Add, Productivity, Reminders, Notifications, Backups, Integrations, Calendars, "+ Add team"). Account panel: Plan "Beginner" + Manage plan, Photo (Change/Remove), Name, Email (Change email), Password (Change password), 2FA toggle (disabled), Connected accounts (Google, Facebook, Apple, each with Disconnect), Delete account.
9. **Label view (sidebar clarification)** — /app/label/clients-…. Clicking "Clients" in the sidebar opened a label view, not a project: sidebar Favorites mix projects, labels, and filters with identical styling.

## Left sidebar (same on all screens, top to bottom)

- Account button "C0ach" (menu: account, Settings, Add a team, Reporting, Print, What's new, Latest experiments, Upgrade to Pro, Sync, Log out; version v11893 beta), notifications bell, sidebar toggle, red "+ Add task", "Dictate tasks with Ramble".
- Main filters: Search, Inbox (305), Today (329), Upcoming, Filters & Labels, Reporting.
- Favorites (collapsible, expanded): 21 entries with task counts and More-actions menus — including Attio CRM Automation Buildout (20), EAGLE EYE VISION LABZ, LLC. (22), Biz-Opz-Main-Lab (64), Podcast Workflow (22), M3ta'z a.Eye Labz.ai (102), M3TA-0S INT3LLIG3NCE SUIT3 (38), M3TA-OS High-ROI Sprint (35), FNPC (8), and the three saved filters. Several marked "View-only project".
- "My Projects USED: 83/5" with projects menu and list toggle; "Help & resources" at the bottom. Long names truncate.

## Behavior notes for the clone

- Today/Inbox/project views are horizontal board columns; Upcoming and Filters & Labels are vertical lists.
- Task cards everywhere: circular checkbox, title, date, labels, project.
- Sidebar favorites deliberately mix projects, labels, and filters — the clone's sidebar model should treat them as one list of saved views (matches the spec's SidebarItem enum ruling in Gotchas).
- View-only banners are a plan artifact, not app behavior — excluded from the clone.

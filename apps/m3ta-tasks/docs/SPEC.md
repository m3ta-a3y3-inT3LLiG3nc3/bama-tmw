# M3taTasks (working title)

A native Mac to-do app that clones the structure and behavior of Todoist for one person's task capture: Inbox, Today, projects, and check-off, with local data and no account. Replaces: Todoist, for M3ta's personal task capture on the Mac. Taken from the Todoist web walkthrough (screen index pending, slots below).

## Brief

```markdown
# M3taTasks (working title)

A native Mac app that captures tasks fast, shows Today, organizes by
project, and checks tasks off, for M3ta. A personal clone of Todoist's
structure and behavior, rebuilt with native Mac controls.

## Replaces
Todoist (the paid account and the web tab) for personal task capture
on the Mac.

## Main jobs
1. Capture a task fast: type a title, press Return, it is in the Inbox.
2. See Today: everything due today, in one list, first thing.
3. Organize: projects in the sidebar, a task belongs to one project.
4. Complete a task: one click on its circle, it leaves the list and
   lands in Completed with a timestamp.

## Data
- Task: title, notes, isCompleted, completedAt, createdAt, dueDate
  (optional, nil by default), sortOrder. SwiftData, local store.
- Project: name, colorName, sortOrder, isArchived. SwiftData. (M2 —
  the type is defined with the model so seed data stays honest; its
  UI ships in M2.)
- View state: selected sidebar page, window frame. UserDefaults.

## Shape
One window, NavigationSplitView: sidebar, list, detail popover.
macOS 26 or later. Local data. Works offline. No accounts, no sync.

## System hooks
None in version one. (Global quick-add shortcut and menu bar extra
are M4/M5 in the stories ladder, not v1.)

## Reference
Todoist web app, walked with the clone skill: docs/screens/INDEX.md
(pending capture — see the SCREEN INDEX slots in the draft that
carries this spec).

## Look
Native, system accent color, Apple's own controls. Not Todoist's
look: no red brand accent, no copied icons or words.

## Not in version one
- Todoist account, sign-in, or any sync (local only; iCloud later
  only if M3ta asks)
- Sections, labels, filters (stories parked in M2/M4 and Later)
- Recurrence and reminders (M3)
- Sharing, comments, activity feed, Karma, integrations,
  upgrade prompts (Dropped, listed in the stories)
```

## How it works

| Part | API | Permission |
| --- | --- | --- |
| Data store | SwiftData `ModelContainer`, one local store (the new-mac-app template's database location) | None |
| App shell | SwiftUI `NavigationSplitView`: sidebar, list, detail | None |
| Sidebar pages | `SidebarItem` enum (template): `inbox`, `today`, `completed`, later `project(Project)` — smart lists filter the one Task model | None |
| Today smart list | SwiftData `#Predicate` on `dueDate` in [startOfToday, startOfTomorrow) and `isCompleted == false` | None |
| Add / edit | Inline add row at the top of the list; task detail as a popover with title, notes, and a date picker | None |
| Complete | Checkbox circle in the row; sets `isCompleted` and `completedAt` | None |
| View state | `UserDefaults` via `@AppStorage` | None |
| Snapshots | Template snapshot mode (`APP_SNAPSHOT`, `APP_SEED=1`): one PNG per sidebar page, light and dark | None |

Main types:

- `Task`: `@Model`. Fields as in the Brief. `dueDate` is optional from day one so M3 needs no migration; new SwiftData fields always get defaults (improve-loop rule).
- `Project`: `@Model`. Defined in M1's model file, unused by M1 UI; its stories are M2.
- `SidebarItem`: enum of pages. Every page the app grows goes here so snapshot mode visits it.
- `AppModel`: `@Observable`. Selected page, the task being edited, add-field state.
- `TaskQueries`: pure functions that return the SwiftData predicate for a page (Inbox: not completed; Today: not completed and due today; Completed: completed, newest first). Unit tested.

Behaviors that matter:

- **One task, many lists.** A task lives once. Inbox shows every uncompleted task; Today also shows it when it is due today. Completing it removes it from both and files it in Completed, grouped by completion day.
- **Add is inline, never a dialog.** The add row sits at the top of the list (Todoist puts it at the top of Inbox and inside each day/project). Return saves and keeps focus in the field for the next task; Escape clears and dismisses.
- **Dates are set one way in M1.** The detail popover's date picker sets or clears `dueDate`. Natural-language dates ("tomorrow", "every Friday") are M3/M4 stories, not v1 — the clone walk's date-parsing findings land in the screen index, not in M1 code.
- **Delete is final in v1.** Detail popover and context menu both offer Delete. There is no trash and no undo in M1; the gotcha below is why that is stated, not hidden.
- **Seed data obeys the stories.** Seed tasks use only title, dueDate, and completed state — every attribute the seed sets is one an M1 story lets the user create (user-stories rule).

## Stories

```markdown
## M1 Core loop

### S-001 App shell with Inbox, Today, and Completed pages
As the user, I open the app and see a sidebar with Inbox, Today, and
Completed, a task list, and the Inbox selected.
Screens: 01-inbox.png, 02-today.png, 12-completed.png (pending capture)
Acceptance:
- [snap] Snapshot mode renders the three pages in light and dark; the
  sidebar order is Inbox, Today, Completed.
- [self] The app launches to the page selected at last quit.
- [unit] `TaskQueries` returns an uncompleted task for Inbox, and never
  for Completed.
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

### S-002 Add a task to the Inbox
As the user, I type a title in the add row at the top of the Inbox and
press Return; the task appears and the field is ready for the next one.
Screens: 01-inbox.png, 08-quick-add.png (pending capture)
Depends: S-001
Acceptance:
- [self] Return saves the task and keeps focus in the add row; Escape
  clears the field and saves nothing.
- [unit] A whitespace-only title saves nothing.
- [snap] With seed data on, the new task renders as the first row under
  the add row.
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

### S-003 Task rows show title and due date
As the user, I read each row at a glance: completion circle, title, and
its due date when it has one.
Screens: 01-inbox.png, 02-today.png (pending capture)
Depends: S-002
Acceptance:
- [snap] A task due today shows "Today" on the row; a task with no date
  shows nothing where the date would be.
- [unit] Row date text comes from `dueDate` only: today, tomorrow, or a
  short date; a completed task never shows a date.
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

### S-004 Complete a task
As the user, I click a task's circle and it leaves Inbox and Today and
appears in Completed with the time I finished it.
Screens: 01-inbox.png, 12-completed.png (pending capture)
Depends: S-003
Acceptance:
- [self] The circle fills, the row leaves the list, and Completed shows
  the task under today's heading within the same session.
- [unit] Completing sets `isCompleted` and stamps `completedAt`;
  uncompleting from Completed clears both and returns the task.
- [manual] Quit and relaunch: the task is still in Completed (the core
  loop survives a restart).
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

### S-005 Edit a task in its detail popover
As the user, I click a task and edit its title and notes in a popover;
clicking away saves.
Screens: 07-task-detail.png (pending capture)
Depends: S-003
Acceptance:
- [self] Editing the title and pressing Return updates the row without
  reopening the popover.
- [snap] The popover shows title field, notes area, date row, and a
  Delete button, in light and dark.
- [unit] Clearing the title to empty reverts to the previous title on
  dismiss; a task is never saved title-less.
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

### S-006 Set a due date and see the task in Today
As the user, I set today's date on a task in its detail popover and it
appears in Today as well as the Inbox.
Screens: 07-task-detail.png, 02-today.png (pending capture)
Depends: S-005
Acceptance:
- [unit] The Today predicate includes a task due at 23:59 today and
  excludes one due at 00:00 tomorrow.
- [self] Setting the date to today moves the task into Today without a
  relaunch; clearing the date removes it from Today only.
- [snap] Today's snapshot with seed data shows only tasks due today.
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

### S-007 Delete a task
As the user, I delete a task from its detail popover or its context
menu, and it is gone from every page.
Screens: 07-task-detail.png, 09-task-context-menu.png (pending capture)
Depends: S-005
Acceptance:
- [self] Delete asks once ("Delete this task?") and then removes the
  task from Inbox, Today, and Completed in the same session.
- [unit] Deleting removes the row from the store; a relaunch does not
  bring it back.
UX: pending (ux-design pass on the Mac, before this story is coded)
Status: todo

## M2 Organize (parked — written, not in the M1 build order)

### S-008 Create, rename, and delete a project
As the user, I add a project in the sidebar, rename it from its context
menu, and delete it; its tasks fall back to the Inbox.
Screens: 05-project-view.png, 09-task-context-menu.png (pending capture)
Depends: S-001
Acceptance:
- [snap] The sidebar lists projects under the three smart pages, in
  sort order, in light and dark.
- [unit] Deleting a project clears the project link on its tasks; no
  task is deleted with its project.
Status: todo

### S-009 File a task under a project
As the user, I pick a project in a task's detail popover and the task
shows on that project's page and in the Inbox no longer.
Screens: 05-project-view.png, 07-task-detail.png (pending capture)
Depends: S-008, S-005
Acceptance:
- [self] Moving a task updates both pages in the same session.
- [unit] A task has at most one project; Today still shows it when due.
Status: todo

### S-010 Sections inside a project
As the user, I add a section to a project and drag or file tasks under
it; the project page groups tasks by section.
Screens: 05-project-view.png (pending capture)
Depends: S-009
Acceptance:
- [snap] The project page renders section headings with their tasks;
  tasks with no section sit above the first heading.
- [unit] Deleting a section keeps its tasks, unsectioned.
Status: todo

## M3 Time (parked — written, not in the M1 build order)

### S-011 Upcoming view
As the user, I open Upcoming and see uncompleted tasks with dates,
grouped by day, for the next weeks.
Screens: 03-upcoming.png (pending capture)
Depends: S-006
Acceptance:
- [snap] Days render as section headings in date order; a day with no
  tasks still shows its heading and an add row.
- [unit] A task due in 30 days appears; a task with no date never does.
Status: todo

### S-012 Recurring due dates
As the user, I set a task to repeat (daily, weekly, monthly, or a
custom phrase) and completing it schedules the next one.
Screens: 07-task-detail.png (pending capture)
Depends: S-006
Acceptance:
- [unit] Completing a weekly task sets its next due date seven days
  out and clears its completed state.
- [self] The detail popover shows the recurrence in words next to the
  date.
Status: todo

### S-013 Reminders
As the user, I set a time on a due date and the Mac notifies me then.
Screens: 07-task-detail.png, 11-settings.png (pending capture)
Depends: S-006
Acceptance:
- [manual] A reminder set one minute out fires a notification while
  the app is closed.
- [self] Denying notification permission shows one line in Settings
  saying reminders are off, and nothing breaks.
Status: todo

## Later
- Filters & Labels pages (reference: 04-filters-labels.png, pending capture) — saved filters as sidebar pages; labels on tasks.
- Board view for a project (reference: 06-project-board.png, pending capture).
- Search across tasks (M4 Speed).
- Global quick-add panel with a system shortcut and natural-language dates (M4 Speed; date phrases probed in the capture pass, see the screen index).
- Full keyboard navigation and menu command map (M4/M6).
- Menu bar extra, Shortcuts actions, agent CLI (M5 System).
- Drag and drop between days and projects, empty-state art, app icon final pass (M6 Polish).

## Dropped
- Todoist account and sign-in
- Sync of any kind in v1 (data is local; iCloud is a later decision)
- Sharing, collaborators, comments, activity feed
- Karma, streaks, productivity gamification
- Integrations (calendar, email, third-party apps)
- Upgrade prompts and plan tiers
- Todoist's words, icons, logo, and brand color (structure and behavior only)
```

## Gotchas

- The reference is a **web app, not the native app**. Todoist also ships an Electron Mac app; this clone follows the web walkthrough the capture pass is making. Web screenshots carry browser chrome and web sizing — they are evidence for structure and behavior, never pixel targets. Where the reference uses a web-style custom control and macOS has a native one (toolbar, sidebar, context menu, date picker), the native one wins (improve-loop compare rule).
- The web app has **no menu bar to walk**. The clone skill's menu-bar step has no web equivalent; the native app takes the template's standard menus (app, File, Edit, View, Window) and the command map in the screen index records what the web top bar and menus actually hold instead.
- A web walk cannot show the desktop app's system behaviors: global quick-add shortcut, notifications, offline queueing. Those are M3-M5 stories decided from the brief, not from screenshots — do not claim the index proves them.
- Todoist's quick add parses dates from the title text. Probing that field with phrases is safe and is how the capture pass should test it (preview fields test behavior without saving); typing in the real account's add field and pressing Return is not a probe — it creates a real task in M3ta's data. Escape, always.
- The capture runs on M3ta's real, signed-in Todoist. Screenshots will contain real task titles. Keep the PNGs out of public repos (`.gitignore` gets `docs/screens/*.png`) and note any change to the data during the walk, even an uncertain one (clone skill rule).
- SwiftData migrations: `dueDate` and the `Project` type exist in the model from the first commit precisely so M2/M3 add UI, not schema surgery. Any later field still ships with a default value.
- Snapshot mode only visits pages registered in the `SidebarItem` enum. A new page that is not in the enum ships with no snapshot and fails the milestone's light-and-dark check silently.
- Delete in v1 is permanent and confirmed once. If M3ta wants a trash or undo, that is a new story — do not let it sneak into S-007 as a half-built banner.

Done when M1 is usable for a day: the app opens to the sidebar (Inbox, Today, Completed), a task can be added in the Inbox, checked off into Completed, edited, dated into Today, and deleted, and all of it survives a quit and relaunch with local data only — verified by the light-and-dark snapshot set and the M1 acceptance lines above.

---


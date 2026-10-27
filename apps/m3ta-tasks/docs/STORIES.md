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

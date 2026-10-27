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

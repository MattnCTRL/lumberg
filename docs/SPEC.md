# Lumberg: spec rundown

Status on 2026-11-16: working build, installed on one Mac, in daily use as of today. Single user, not packaged for anyone else yet.

## What it is

Lumberg is a native Mac app that runs one working day. It reads the calendars, fits the task list into the free time between meetings, runs a focus timer, and nags with pop-ups when it is time to start, take a break or go to a meeting. It also keeps a list of projects with weekly hour budgets, and it reads each project's folder to record what actually got done. The theme is the boss from Office Space.

## The day view

- Three columns: the day's timeline (meetings, focus blocks, breaks), the timer, and the task list.
- Tasks are added in one line: a title, with optional length, priority and tag, for example "Draft outline 45m !1".
- The planner places open tasks into free time as focus blocks and breaks. It replans when a meeting moves or a task is finished. A task that does not fit is marked as unscheduled.
- Defaults: 8:00 to 5:00 workday, 25 minute focus blocks, 5 minute breaks, a 15 minute break after every fourth block, and focus ends 5 minutes before a meeting. All of these are settings.

## Timer and pop-ups

- Start, pause, extend and stop a focus block. "I need a break" credits the time worked so far and starts a short break.
- Pop-ups appear in the top-right corner on every desktop and do not take keyboard focus. They fire when a block ends, when a break ends, 5 minutes before a meeting, at the end of the day, and every 5 minutes during work hours when nothing is running.
- Three sizes: the full window, a small floating box when the window is minimised, and the pop-ups. The app stays in the menu bar when the window is closed.

## Calendars

- Lumberg reads whatever calendars macOS already has, so Google and Microsoft accounts are added once in System Settings. There is no separate sign-in.
- Every enabled calendar is merged at read time. Nothing is copied between calendars.
- A calendar with no feed can be added from a photo. Claude reads the photo, the events are listed for approval before anything is added, and they expire after two weeks.

## Projects

- A dedicated Projects screen. Each project has a name, who it is for, a priority, hours per week, an optional deadline, a task backlog, and an optional folder.
- "Plan my day" takes what is left of each project's weekly hours, spreads it over the rest of the week, and proposes what to pull into today's free time. Nothing is added until it is approved.
- Time on a project's tasks counts toward its weekly hours.

## Work capture

- A project's folder can be on this Mac, on a plugged-in drive, or on another Mac reached over SSH.
- Lumberg reads the last 7 days of the folder for: git commits, requests typed to Claude Code there, files Claude Code edited, dated session notes, and, where there is no git, the names of files changed each day.
- It is read-only. For notes and plain files it reads names only, never contents. It skips hidden files and anything that looks like a key or secret.
- Each day gets a card listing what was found, with each item marked as inside or outside a focus block on that project.
- "Write it up" has Claude turn a day's record into a few lines on what got done. "Copy" puts the record on the clipboard.
- A scan runs when a focus block on the project ends, when the Projects screen opens, and on demand.

## Project dossiers

Each project has a dossier: a Markdown file in `~/lumberg/dossiers/<slug>.md` (`LUMBERG_DOSSIERS` moves the folder; a redirected `LUMBERG_HOME` keeps its own). It is the project's long-lived record, and the list of dossiers is the list of ongoing projects. The format is in `dossiers/README.md`.

- A dossier nobody has yet becomes a project. A project made in the app gets a dossier written for it.
- The header carries the settings (name, client, status, priority, weekly hours, deadline, folder, host). Editing the file changes the project the next time the Projects screen opens; editing the project in the app rewrites those header lines at once.
- Lumberg keeps one block current, between `<!-- lumberg:auto:start -->` and `<!-- lumberg:auto:end -->`: focus time this week and over four weeks, open tasks, and the captured work day by day. It never touches the rest of the file, except to add a dated line to the Log when a note is typed in the app.
- Deleting a project sets the dossier's status to `removed` and leaves the file.
- A project with no weekly hours is tracked but not budgeted: it is left out of Plan my day and the quick switch buttons, and its folder is read when it is opened rather than every time the screen opens.

## Work that was not planned

- Lumberg estimates time worked from Claude Code activity and commits in the folder. Activity less than 30 minutes apart counts as one stretch.
- On a project, each day shows how much of that time no focus block covered. "Log it" counts it toward the project's hours.
- Folders worked in today that belong to no project are listed as "Not budgeted today", each with a button to make it a project.

## End of day report

The "TPS report" shows focus blocks, focus time, tasks done, hours per project this week, work captured per project, work that was not budgeted, where the time went, and what carries over. It copies as plain text.

## How it is built

- Swift and SwiftUI, macOS 15 or later. The planning and parsing logic is a separate package with 30 automated tests.
- Calendars come through Apple's EventKit. Claude work runs through Claude Code on the Claude subscription.
- All data is one local file on the Mac. There is no server and no account.

## Limits today

- One folder per project.
- The time estimate only sees Claude Code activity and commits. It includes time Claude was running unattended, and sessions running side by side overlap, so per-project times cannot be added into a day total.
- The scan looks back 7 days.
- One Mac, one user. No sync, no sharing.

## Not built yet

- Events from one calendar outranking the others, with conflicts flagged.
- A nested work breakdown inside a project.
- Status reports per project over a week or longer.
- A way for other tools to read Lumberg's plan and record.
- Limiting a task to part of a day.

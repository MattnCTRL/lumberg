# Lumberg

"Yeah, I'm gonna need you to go ahead and start that focus block."

Lumberg is a Mac app that runs my working day. It reads my calendars, fits my task list into the gaps between meetings, runs the timer, and nags me when it's time to start, stop, or go to a meeting. It also keeps a list of projects with weekly hour budgets and checks each project's folder to see what actually got done.

I built it because I juggle work for several clients and kept ending the week with no idea where the hours went. Every planner I tried either ignored my calendar or wanted me to move my whole life into it. This one sits on top of what macOS already knows and stays out of the way until it's time to bug me.

It is a personal tool. It works, I use it every day, and it has opinions that fit my setup. More on that under [Rough edges](#rough-edges).

## What it does

**Plans the day.** Three columns: the timeline (meetings, focus blocks, breaks), the timer, and the task list. Tasks go in as one line:

```
Draft outline 45m !1 #work
```

That is a title, a length, a priority and a client tag. The planner drops open tasks into free time as focus blocks with breaks between them, and replans when a meeting moves or a task gets finished. Anything that doesn't fit is marked unscheduled instead of quietly disappearing.

**Nags.** Pop-ups show in the top-right corner on every desktop and never steal keyboard focus. They fire when a block ends, when a break ends, five minutes before a meeting, at the end of the day, and every five minutes during work hours if nothing is running. Close the window and it shrinks to a small floating timer; it also lives in the menu bar.

**Reads the calendars you already have.** Anything added in System Settings (Google, Exchange, iCloud) shows up through EventKit. There's no separate sign-in and nothing gets copied between calendars.

**Imports a calendar from a photo.** One of my calendars lives on a locked-down work machine with no feed I can subscribe to. So I take a picture of the screen, Claude reads the events out of it, and Lumberg lists them for approval before adding anything. Imported events expire after two weeks. If that calendar shows its times in another time zone, say which one in the config file and they are converted to yours.

**Budgets projects.** Each project has a client, a priority, hours per week, an optional deadline, a backlog and a folder. "Plan my day" (⌘P) takes what's left of each project's weekly hours, spreads it over the rest of the week and proposes what to pull into today. Nothing is added until you say so.

**Captures the work.** For each project folder it reads the last seven days of git commits, Claude Code sessions, dated session notes and, where there's no git, the names of files that changed. The folder can be local, on an external drive, or on another Mac over SSH. It is strictly read-only, reads names rather than contents for notes and plain files, and skips anything that looks like a key or secret. Work that happened outside a focus block is flagged so you can log it.

**Writes the TPS report.** End of day: focus time, tasks done, hours per project this week, what was captured, what wasn't budgeted, and what carries over. Copies as plain text.

**Keeps a dossier per project.** A Markdown file per project in `dossiers/`. The header holds the settings, the body is prose you write, and Lumberg keeps one marked block up to date with tracked time and captured work. Edit the file and the app picks it up; edit the project in the app and the file is updated. The format is in [dossiers/README.md](dossiers/README.md).

## Building it

You need macOS 15 or later, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/MattnCTRL/lumberg.git
cd lumberg
scripts/build.sh            # builds build/Build/Products/Release/Lumberg.app
scripts/build.sh --install  # also copies it to /Applications and opens it
```

The first launch asks for calendar access. The photo import and the "Write it up" button need either [Claude Code](https://claude.com/claude-code) installed and signed in, or an Anthropic API key entered in Settings. Everything else works without them.

To look around without touching real data:

```sh
open build/Build/Products/Release/Lumberg.app --args --demo
```

## Tests

The planning, parsing and dossier logic is a plain Swift package with no UI in it:

```sh
cd Core && swift test
```

## Layout

```
Core/       LumbergCore: planner, task parser, dossier format, work evidence. Pure Swift, tested.
Lumberg/    The app: SwiftUI views, calendar access, pop-ups, folder scanning, storage.
dossiers/   Dossier format and an example. My own dossiers are not in the repo.
docs/       SPEC.md, the longer rundown of how everything behaves.
scripts/    build.sh and the icon generator.
project.yml XcodeGen project definition. The .xcodeproj is generated, not checked in.
```

## Where things are stored

Everything is one JSON file at `~/Library/Application Support/Lumberg/state.json`. There is no server and no account. Two environment variables move things around, mostly for testing:

- `LUMBERG_HOME` puts the state file somewhere else.
- `LUMBERG_DOSSIERS` points at a different dossier folder.

## Your own clients

Out of the box the tags are Work, Client and Personal. To use your own, put a `config.json` next to the state file:

```json
{
  "clients": [
    { "id": "acme", "label": "Acme", "short": "ACME", "color": "green", "aliases": ["ac"] },
    { "id": "personal", "label": "Personal", "short": "ME", "color": "amber", "aliases": ["me"] }
  ],
  "photoCalendar": { "name": "Acme", "zone": "America/Los_Angeles" }
}
```

`id` is what goes after `#` in a task and in a dossier's `client:` line. Colours are blue, green, red or amber. `photoCalendar` names the calendar you import from photos and the time zone it shows; leave it out and photo times are read in your own zone.

## Rough edges

- The client list is set in a JSON file, not in the app. There's no screen for it yet.
- The dossier folder defaults to `~/lumberg/dossiers`, which assumes the repo is cloned to your home folder. Set `LUMBERG_DOSSIERS` if it isn't.
- One folder per project.
- The time estimate only sees commits and Claude Code activity, so it misses work done anywhere else.
- One Mac, one user. No sync.
- The build signs with whatever Xcode finds. You may have to set your own team in `project.yml`.

## Why the name

Bill Lumbergh, the boss from *Office Space*, minus the h. He'd love this app.

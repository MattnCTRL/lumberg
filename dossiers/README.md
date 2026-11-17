# Project dossiers

One file per ongoing project. Lumberg reads this folder: every dossier here is a project in Lumberg, and the list of files is the project list. My rule for what belongs here: if I worked on it in the last four weeks, it is ongoing.

My own dossiers are not in the repository, since they describe client work. `_example.md` shows the shape. Files starting with `_` are skipped.

## Format

```
---
lumberg: 1                 marks the file as a dossier
slug: portal             same as the file name
name: Portal
client: client             a tag id from your config: work | client | personal by default
status: active             active | paused | done | removed
priority: 2                1 high, 2 normal, 3 low
weekly_hours: 6            0 means tracked but not budgeted
deadline: 2026-12-23       or empty
folder: ~/portal         where the work is; its commits and Claude Code sessions are read
host:                      SSH host when the folder is on another Mac
remote: ...                any other keys are kept as written
---
# Name
## What it is              first paragraph is shown in Lumberg
## Where it lives
## Current state
## Open and next
## Notes elsewhere        pointers to where the detail is kept
<!-- lumberg:auto:start --> … <!-- lumberg:auto:end -->     Lumberg rewrites this block
## Log                     dated lines, newest last
```

## Who writes what

- **Lumberg** writes the header keys listed above, the block between the two markers, and new lines at the end of the Log. It leaves everything else exactly as it found it.
- **Anyone else** (you, a script, another tool) may edit the prose sections and the header. Lumberg picks the changes up the next time its Projects screen opens. Do not edit inside the markers.
- When a piece of work on a project wraps up, bring "Current state" and "Open and next" up to date and add a Log line.
- To add a project, add a file. To drop one, set `status: removed` (or delete it in Lumberg, which does that).

## Notes elsewhere

A dossier points at wherever the detail lives rather than repeating it. Never put a credential in a dossier.

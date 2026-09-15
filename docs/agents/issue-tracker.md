# Issue tracker: GitHub

Scope: patrykseweryn-digica/dotfiles.
Use the gh CLI with --repo patrykseweryn-digica/dotfiles.
Issues, specs, and tickets live in GitHub Issues.

Read the full issue body, labels, and comments before working.
Publish one issue per approved ticket, blockers first.
Apply ready-for-agent to fully specified implementation tickets.
Do not modify or close a parent issue when publishing child tickets.

## Blocking

Use native GitHub issue dependencies, with blocker database IDs.
Also list blocking issue references in each ticket's Blocked by section.
If native dependencies are unavailable, use those references as fallback.
A ticket can start only when all blockers are closed.

## Wayfinding

A map is one issue labelled wayfinder:map.
Link child tickets as native sub-issues.
If unavailable, use a map task list and a Part of reference on each child.
Use wayfinder:research, wayfinder:prototype, wayfinder:grilling,
or wayfinder:task for children.
Work unassigned children whose blockers are closed; claim before working.
Record results before closing a ticket.

## Pull requests as a triage surface

PRs as a request surface: no.

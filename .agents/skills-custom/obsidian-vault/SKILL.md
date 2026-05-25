---
name: obsidian-vault
description: Search, create, edit, summarize, and organize notes in the user's Obsidian vault. Use when user wants to save learnings, create notes, find previous research, look up what was written about a topic, organize or clean up notes, summarize a folder, persist knowledge from a conversation, or mentions "vault", "obsidian", "notatki", "zapisz to", "dodaj do notatek". Also trigger when user says things like "co mam na temat X", "znajdź notatkę o", "zapisz to co się nauczyłem", or wants to save meeting notes.
---

# Obsidian Vault

## Vault

Path (detect which exists):
- macOS: `~/Documents/just-stefan-things/`
- Linux: `~/Documents/Obsidian/just-stefan-things/`

## Folder structure

The vault uses folders for organization. Main folders:

- **Firma/** — work (Digica company, business, sales, projects like Fortem)
- **Inbox/** — quick, unsorted notes for later organization
- **Kuchnia/** — cooking, recipes, drinks
- **Nauka/** — science & learning
- **Osiąganie swoich celów/** — goals, habits, productivity
- **Osobiste/** — personal (health, contacts, jokes, sport, travel, dreams)
- **Polityka/** — politics
- **Programowanie/** — programming (ML, Python, Front-End, DevOps, Git, architecture)
- **Projekty/** — side projects
- **Wiara/** — faith, reflections, retreats
- **Zapiski & Notatki/** — writings (daily notes, reflections/przemyślenia, books, essays)

## Rules

### Before saving — always show first

Never write directly to the vault without showing the user the full content first. Present the note in chat and wait for explicit approval before saving. This is non-negotiable.

### Choosing the right folder

- If the note clearly fits an existing folder → use it
- If unsure or it could go in multiple places → ask the user which folder
- Quick, rough notes → `Inbox/`
- Polished, topic-specific notes → directly to the right folder
- **Never create new folders without asking first.** Propose the folder name and location, wait for approval.

### Daily Notes — off limits

The `Zapiski & Notatki/Daily Notes/` folder is the user's private journaling space. Never read, create, or modify files there.

### Note naming

Use short, descriptive titles. Language matches the note content (Polish topics → Polish title, tech topics → English title).

Good: `Memory Management in Python.md`, `Jak robić przeglądy tygodniowe.md`
Bad: `notatka-2025-03-18.md`, `Untitled.md`

### Language

Match language to topic:
- **Technical/programming** → English
- **Personal, reflections, work, faith, goals** → Polish
- When unclear, default to the language the user used in the request

### Note length

Keep notes concise — 5-20 lines, bullet points preferred. The goal is to capture the essence, not write an essay. Longer only when the topic genuinely demands it.

### Wikilinks

Add `[[wikilinks]]` to related existing notes at the bottom of each new note, under a `## Powiązane` section. Before adding links, search the vault (Glob/Grep) to find genuinely related notes. Only link notes that are actually relevant — don't force connections.

Example:
```markdown
## Powiązane
- [[Memory Management in Python]]
- [[Python Multithreading and Multiprocessing Tutorial]]
```

### Tags

Add 2-4 tags at the very end of the note. Tags should be lowercase, in the language of the note content. Use existing tags from the vault when possible — search with Grep for `^#[a-z]` to find what's already used.

Example:
```markdown
#python #performance #memory
```

### Editing existing notes

When the user asks to update a note, read it first, then propose changes in chat. Wait for approval before writing. Prefer appending new sections over modifying existing content.

## Workflows

### Search for notes

**By filename:**
First determine the vault path: use `~/Documents/just-stefan-things/` if it exists (macOS), otherwise `~/Documents/Obsidian/just-stefan-things/` (Linux). Use Glob with that path and pattern `**/*keyword*`.

**By content:**
Use Grep with the vault path (determined above) and the search term.

**Find backlinks to a note:**
Use Grep with pattern `\[\[Note Title\]\]` across the vault.

When the user asks a question about their notes:
- If they want a list → show matching file names and paths
- If they want to know what they wrote → read the notes and summarize

### Create a new note

1. Draft the note content following the rules above (language, length, wikilinks, tags)
2. Choose the target folder (or ask if unsure)
3. **Show the full note to the user in chat** with proposed filename and folder
4. Wait for "OK" / approval
5. Write the file using Write tool

### Summarize a folder

When asked to summarize a folder or topic:
1. List all notes in the folder with Glob
2. Read them (or a representative sample if too many)
3. Present a concise summary: main themes, key notes, how many notes

### Organize / clean up

When asked to organize notes:
1. Scan the target area
2. Identify issues: duplicates, notes in wrong folders, notes that could be merged
3. Present a plan to the user — what to move, rename, merge
4. Execute only after approval

---
name: obsidian-notes
description: "Search, create, edit, summarize, and organize notes in the user's Obsidian vault."
---

# Obsidian Vault

Use this skill for requests about the user's Obsidian vault: finding notes, saving learnings, creating notes, updating notes, summarizing folders/topics, organizing notes, or answering "what have I written about X?"

## Vault

Detect the first path that exists:
- macOS: `~/Documents/just-stefan-things/`
- Linux: `~/Documents/Obsidian/just-stefan-things/`

Use the current agent's available file search, read, write, move, and edit capabilities. Do not depend on host-specific tool names.

## Hard Safety Rules

- Never write, edit, move, rename, or delete vault files without showing the full proposed content or plan and receiving explicit user approval.
- Never read, create, modify, move, or summarize files in `Zapiski & Notatki/Daily Notes/`.
- Never create new folders without asking first. Propose folder name and location, then wait for approval.
- For existing-note edits, read the note first, propose the change in chat, and wait for approval before writing.

## Workflow Router

- **Search/read**: search by filename/content/backlinks; avoid Daily Notes; summarize or list results as requested.
- **Create**: draft note; choose folder; add related links/tags when useful; show filename, folder, and full content; wait for approval; write.
- **Edit**: read target note; propose appended section or exact change; wait for approval; write.
- **Summarize**: list notes in target folder/topic; read relevant notes or a representative sample; summarize themes, key notes, and count.
- **Organize**: scan target area; identify duplicates, wrong folders, rename/merge candidates; present plan; execute only after approval.

## References

- Read `references/folders.md` when choosing a destination folder or interpreting vault areas.
- Read `references/style.md` before drafting or editing note content.
- Read `references/workflows.md` when the request needs detailed search/create/edit/summarize/organize steps.

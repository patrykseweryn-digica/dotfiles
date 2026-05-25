# Obsidian Vault Workflows

Use the current agent's available file search, read, write, edit, and move capabilities. Do not depend on host-specific tool names.

## Search For Notes

Determine the vault path first:
- macOS: `~/Documents/just-stefan-things/`
- Linux: `~/Documents/Obsidian/just-stefan-things/`

Search modes:
- By filename: search for matching note names under the vault path.
- By content: search note contents under the vault path.
- Backlinks: search for `[[Note Title]]` across the vault.

When the user asks a question about notes:
- If they want a list, show matching file names and paths.
- If they want to know what they wrote, read relevant notes and summarize.

Do not search or read `Zapiski & Notatki/Daily Notes/`.

## Create A New Note

1. Read `style.md` and `folders.md`.
2. Draft the note content following language, length, wikilinks, and tag rules.
3. Choose the target folder, or ask if unsure.
4. Show proposed filename, folder, and full note content in chat.
5. Wait for explicit approval.
6. Write the file.

## Edit An Existing Note

1. Read the target note first.
2. Prefer appending new sections over modifying existing content.
3. Show the proposed change in chat.
4. Wait for explicit approval.
5. Write the change.

## Summarize A Folder Or Topic

1. List notes in the folder or matching topic.
2. Read relevant notes, or a representative sample if too many.
3. Present main themes, key notes, and count.

Do not summarize Daily Notes.

## Organize Or Clean Up

1. Scan the target area.
2. Identify duplicates, wrong-folder notes, rename candidates, and merge candidates.
3. Present a plan with proposed moves, renames, or merges.
4. Execute only after explicit approval.

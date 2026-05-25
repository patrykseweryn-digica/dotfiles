---
name: anki-export
description: "Export flashcard JSON to Anki .apkg decks with the bundled genanki converter."
argument-hint: "[flashcards.json] [--deck name] [--output file.apkg]"
---

# Anki Export

Convert JSON produced by `generate-flashcards` into an Anki `.apkg` deck.

## Use When

- User asks for Anki export, `.apkg`, Anki deck, or importing generated flashcards into Anki.
- Input is already flashcard JSON. If the user provides text/PDF/URL instead, use `generate-flashcards` first.

## Workflow

1. Locate the input JSON.
2. Validate the shape before running:
   - top-level `cards` is a non-empty list
   - each card has `question` and `answer`
   - optional fields may include `topic`, `tier`, `type`, `priority`, `context`, `explanation`, `mnemonic`
3. Use the bundled script. Resolve `scripts/json_to_apkg.py` relative to this skill directory.
4. If `genanki` is missing, install it in the active Python environment only after confirming the project/runtime context.
5. Run a conversion:
   ```bash
   python3 scripts/json_to_apkg.py input.json
   python3 scripts/json_to_apkg.py input.json --deck "Deck Name" --output output.apkg
   ```
6. Report the output `.apkg` path, deck name, exported card count, and warnings.

## Converter Behavior

- Stable GUIDs from question text, so re-imports update matching cards instead of blindly duplicating.
- Tags include available `tier`, `type`, `priority`, and `topic`.
- Backtick-wrapped text becomes inline `<code>`.
- Card appearance lives in `assets/card.css`, `assets/front.html`, and `assets/back.html`.

## Boundaries

- Do not redesign the Anki card template unless the user asks.
- Do not hand-edit `.apkg`; fix JSON or patch the converter.
- Do not invent missing cards. If JSON is malformed or empty, ask whether to regenerate with `generate-flashcards`.

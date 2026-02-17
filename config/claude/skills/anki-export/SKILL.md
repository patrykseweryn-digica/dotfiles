---
name: anki-export
description: Convert flashcard JSON to native Anki .apkg packages. Use when user wants to export flashcards to Anki, create Anki deck, import flashcards into Anki, or convert JSON flashcards for spaced repetition. Triggers on "anki", "export to anki", "anki deck", ".apkg", or requests to convert flashcard files for Anki.
---

# Anki Export

Convert flashcard JSON (from `/flashcards` skill) to native Anki .apkg packages.

## Quick Start

```bash
python scripts/json_to_apkg.py input.json
python scripts/json_to_apkg.py input.json --deck "My Deck" --output ~/decks/output.apkg
```

**Requires**: `pip install genanki` (install if missing)

## Script Arguments

| Arg | Description |
|-----|-------------|
| `json_file` | Path to flashcard JSON (required) |
| `--deck`, `-d` | Deck name (default: JSON topic) |
| `--output`, `-o` | Output path (default: input.apkg) |

## Features

- **Styled cards**: Clean typography with code highlighting
- **Hierarchical tags**: `tier::foundational`, `type::atomic`, `topic::CSS`
- **Stable GUIDs**: Re-importing updates existing cards, doesn't duplicate
- **Code formatting**: Backticks → `<code>` tags with styling

## Input JSON Schema

Expected structure (from `/flashcards` skill):
```json
{
  "topic": "Topic Name",
  "cards": [{
    "id": 1,
    "tier": "foundational|intermediate|advanced",
    "type": "atomic|conceptual|comparison|application|synthesis",
    "question": "Question with `code`?",
    "answer": "Answer text."
  }],
  "stats": {...}
}
```

## Output

- `.apkg` file: Double-click to import into Anki
- Cards display question + tier/type metadata on front, answer on back
- Tags enable filtering by tier, type, and topic in Anki browser

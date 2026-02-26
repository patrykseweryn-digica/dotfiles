---
name: anki-export
description: Convert flashcard JSON to native Anki .apkg packages. Use when user wants to export flashcards to Anki, create Anki deck, import flashcards into Anki, or convert JSON flashcards for spaced repetition. Triggers on "anki", "export to anki", "anki deck", ".apkg", or requests to convert flashcard files for Anki.
---

# Anki Export

Convert flashcard JSON (from `/flashcards` skill) to native Anki .apkg packages.

## Quick Start

```bash
python3 scripts/json_to_apkg.py input.json
python3 scripts/json_to_apkg.py input.json --deck "My Deck" --output ~/decks/output.apkg
```

**Requires**: `pip install genanki` (install if missing)

## Script Arguments

| Arg | Description |
|-----|-------------|
| `json_file` | Path to flashcard JSON (required) |
| `--deck`, `-d` | Deck name (default: JSON topic) |
| `--output`, `-o` | Output path (default: input.apkg) |

## Features

- **Glass Warm design**: Frosted glass card on warm gradient background with backdrop-filter blur
- **Light + dark mode**: Auto-detects via `.nightMode` (AnkiDroid), `.night_mode`, `prefers-color-scheme` (Desktop)
- **Typography**: Source Sans 3 + Source Code Pro (Google Fonts @import)
- **Hierarchical tags**: `tier::foundational`, `type::atomic`, `topic::CSS`
- **Stable GUIDs**: Re-importing updates existing cards, doesn't duplicate
- **Code formatting**: Backticks → `<code>` pills with warm amber styling

## Card Layout

- **Front**: Context label (top, uppercase) + question
- **Back**: Context + question + separator + answer + optional explanation (muted, below answer) + optional mnemonic (italic, left-bordered)
- All content inside a `.glass` container with rounded corners and backdrop blur

## Input JSON Schema

Expected structure (from `/flashcards` skill):
```json
{
  "topic": "Topic Name",
  "cards": [{
    "id": 1,
    "tier": "foundational|intermediate|advanced",
    "type": "atomic|conceptual|comparison|reverse|application|synthesis",
    "question": "Question with `code`?",
    "answer": "Short answer.",
    "explanation": "Optional 1-3 sentence elaboration (rendered below answer)",
    "context": "[Topic area]",
    "mnemonic": "Optional memory hint (rendered as italic left-bordered extra)",
    "source_detail": "Optional section ref (not rendered)"
  }],
  "stats": {...}
}
```

## Output

- `.apkg` file: Double-click to import into Anki
- Front: context tag + question in glass card
- Back: context + question + answer (+ extra if mnemonic/source present)
- Tags enable filtering by tier, type, and topic in Anki browser

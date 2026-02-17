#!/usr/bin/env python3
"""Convert flashcard JSON to Anki .apkg format using genanki."""

import argparse
import json
import hashlib
import re
import sys

try:
    import genanki
except ImportError:
    print("Error: genanki not installed. Run: pip install genanki", file=sys.stderr)
    sys.exit(1)


def generate_id(seed: str) -> int:
    """Generate a stable numeric ID from a string seed."""
    return int(hashlib.md5(seed.encode()).hexdigest()[:8], 16)


def convert_backticks_to_html(text: str) -> str:
    """Convert markdown backticks to HTML code tags."""
    # Convert inline code `code` to <code>code</code>
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', text)


def create_model(deck_name: str) -> genanki.Model:
    """Create an Anki model with Question/Answer fields and tag display."""
    model_id = generate_id(f"model_{deck_name}")

    return genanki.Model(
        model_id,
        f'{deck_name} Model',
        fields=[
            {'name': 'Question'},
            {'name': 'Answer'},
            {'name': 'Tier'},
            {'name': 'Type'},
        ],
        templates=[{
            'name': 'Card 1',
            'qfmt': '''
<div class="question">{{Question}}</div>
<div class="meta">{{Tier}} · {{Type}}</div>
''',
            'afmt': '''
{{FrontSide}}
<hr id="answer">
<div class="answer">{{Answer}}</div>
''',
        }],
        css='''
.card {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 18px;
    text-align: left;
    color: #333;
    background-color: #fff;
    padding: 20px;
    line-height: 1.5;
}
.question {
    font-size: 20px;
    font-weight: 500;
    margin-bottom: 10px;
}
.answer {
    margin-top: 15px;
}
.meta {
    font-size: 12px;
    color: #888;
    text-transform: capitalize;
}
code {
    background: #f4f4f4;
    padding: 2px 6px;
    border-radius: 3px;
    font-family: "SF Mono", Consolas, monospace;
    font-size: 0.9em;
}
hr#answer {
    border: none;
    border-top: 1px solid #ddd;
    margin: 15px 0;
}
''')


def create_note(model: genanki.Model, card: dict, topic: str) -> genanki.Note:
    """Create an Anki note from a flashcard card dict."""
    question = convert_backticks_to_html(card['question'])
    answer = convert_backticks_to_html(card['answer'])
    tier = card.get('tier', 'unknown')
    card_type = card.get('type', 'unknown')

    # Create tags
    topic_tag = topic.replace(' ', '_')
    tags = [f"tier::{tier}", f"type::{card_type}", f"topic::{topic_tag}"]

    # Generate stable GUID from question content
    guid = genanki.guid_for(card['question'])

    return genanki.Note(
        model=model,
        fields=[question, answer, tier, card_type],
        tags=tags,
        guid=guid
    )


def convert_json_to_apkg(json_path: str, output_path: str | None = None, deck_name: str | None = None):
    """Convert flashcard JSON file to Anki .apkg package."""
    # Read JSON
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Extract info
    topic = data.get('topic', 'Flashcards')
    cards = data.get('cards', [])

    if not cards:
        print("Error: No cards found in JSON file", file=sys.stderr)
        sys.exit(1)

    # Use provided deck name or fall back to topic
    deck_name = deck_name or topic

    # Determine output path
    if not output_path:
        output_path = json_path.rsplit('.', 1)[0] + '.apkg'

    # Create model and deck
    model = create_model(deck_name)
    deck_id = generate_id(f"deck_{deck_name}")
    deck = genanki.Deck(deck_id, deck_name)

    # Add notes
    for card in cards:
        note = create_note(model, card, topic)
        deck.add_note(note)

    # Export package
    package = genanki.Package(deck)
    package.write_to_file(output_path)

    # Report stats
    stats = data.get('stats', {})
    by_tier = stats.get('by_tier', {})
    by_type = stats.get('by_type', {})

    print(f"Exported {len(cards)} cards to {output_path}")
    print(f"\nDeck: {deck_name}")
    if by_tier:
        tier_str = ", ".join(f"{k}: {v}" for k, v in by_tier.items())
        print(f"Tiers: {tier_str}")
    if by_type:
        type_str = ", ".join(f"{k}: {v}" for k, v in by_type.items())
        print(f"Types: {type_str}")
    print(f"\nTo import: Double-click {output_path} or use Anki → File → Import")


def main():
    parser = argparse.ArgumentParser(description='Convert flashcard JSON to Anki .apkg')
    parser.add_argument('json_file', help='Path to flashcard JSON file')
    parser.add_argument('--output', '-o', help='Output .apkg path (default: same as input with .apkg extension)')
    parser.add_argument('--deck', '-d', help='Deck name (default: topic from JSON)')

    args = parser.parse_args()
    convert_json_to_apkg(args.json_file, args.output, args.deck)


if __name__ == '__main__':
    main()

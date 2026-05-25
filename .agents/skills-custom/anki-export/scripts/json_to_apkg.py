#!/usr/bin/env python3
"""Convert flashcard JSON to Anki .apkg format using genanki."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

try:
    import genanki
except ImportError:
    print("Error: genanki not installed. Run: pip install genanki", file=sys.stderr)
    sys.exit(1)


def generate_id(seed: str) -> int:
    return int(hashlib.md5(seed.encode()).hexdigest()[:8], 16)


def convert_backticks_to_html(text: str) -> str:
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', text)


ASSETS_DIR = Path(__file__).resolve().parents[1] / 'assets'


def read_asset(name: str) -> str:
    path = ASSETS_DIR / name
    return path.read_text(encoding='utf-8')


def create_model(deck_name: str) -> genanki.Model:
    model_id = generate_id(f"model_glass_v5_{deck_name}")

    return genanki.Model(
        model_id,
        f'{deck_name} Glass',
        fields=[
            {'name': 'Question'},
            {'name': 'Answer'},
            {'name': 'Meta'},
            {'name': 'Extra'},
            {'name': 'Explanation'},
        ],
        templates=[{
            'name': 'Card 1',
            'qfmt': read_asset('front.html'),
            'afmt': read_asset('back.html'),
        }],
        css=read_asset('card.css'))


def build_extra(card: dict) -> str:
    parts = []
    if card.get('mnemonic'):
        parts.append(card['mnemonic'])
    return ' | '.join(parts)


def build_meta(card: dict) -> str:
    return card.get('context', '').strip('[] ')


def build_tags(card: dict, topic: str) -> list[str]:
    topic_tag = topic.replace(' ', '_').replace('&', 'and')
    tags = []
    if card.get('tier'):
        tags.append(f"tier::{card['tier']}")
    if card.get('type'):
        tags.append(f"type::{card['type']}")
    if card.get('priority'):
        tags.append(f"priority::{card['priority']}")
    tags.append(f"topic::{topic_tag}")
    return tags


def create_note(model, card: dict, topic: str) -> genanki.Note:
    meta = build_meta(card)
    extra = convert_backticks_to_html(build_extra(card))
    tags = build_tags(card, topic)

    question = convert_backticks_to_html(card.get('question', ''))
    answer = convert_backticks_to_html(card.get('answer', ''))
    explanation = convert_backticks_to_html(card.get('explanation', ''))
    guid = genanki.guid_for(card.get('question', f"card_{card.get('id', '')}"))

    return genanki.Note(
        model=model,
        fields=[question, answer, meta, extra, explanation],
        tags=tags,
        guid=guid,
    )


def convert_json_to_apkg(json_path: str, output_path: str | None = None, deck_name: str | None = None):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    topic = data.get('topic', 'Flashcards')
    cards = data.get('cards', [])

    if not cards:
        print("Error: No cards found in JSON file", file=sys.stderr)
        sys.exit(1)

    deck_name = deck_name or topic

    if not output_path:
        output_path = json_path.rsplit('.', 1)[0] + '.apkg'

    model = create_model(deck_name)
    deck_id = generate_id(f"deck_{deck_name}")
    deck = genanki.Deck(deck_id, deck_name)

    for card in cards:
        note = create_note(model, card, topic)
        deck.add_note(note)

    package = genanki.Package(deck)
    package.write_to_file(output_path)

    stats = data.get('stats', {})
    by_tier = stats.get('by_tier', {})
    by_priority = stats.get('by_priority', {})

    print(f"Exported {len(cards)} cards to {output_path}")
    print(f"Deck: {deck_name}")
    if by_tier:
        print(f"Tiers: {', '.join(f'{k}: {v}' for k, v in by_tier.items())}")
    if by_priority:
        print(f"Priority: {', '.join(f'{k}: {v}' for k, v in by_priority.items())}")
    print(f"\nTo import: Double-click {output_path} or use Anki → File → Import")


def main():
    parser = argparse.ArgumentParser(description='Convert flashcard JSON to Anki .apkg')
    parser.add_argument('json_file', help='Path to flashcard JSON file')
    parser.add_argument('--output', '-o', help='Output .apkg path')
    parser.add_argument('--deck', '-d', help='Deck name (default: topic from JSON)')

    args = parser.parse_args()
    convert_json_to_apkg(args.json_file, args.output, args.deck)


if __name__ == '__main__':
    main()

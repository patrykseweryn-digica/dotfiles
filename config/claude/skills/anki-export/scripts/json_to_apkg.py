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
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', text)


def create_basic_model(deck_name: str) -> genanki.Model:
    model_id = generate_id(f"model_v2_{deck_name}")

    return genanki.Model(
        model_id,
        f'{deck_name} Basic',
        fields=[
            {'name': 'Question'},
            {'name': 'Answer'},
            {'name': 'Meta'},
            {'name': 'Extra'},
        ],
        templates=[{
            'name': 'Card 1',
            'qfmt': '''
<div class="question">{{Question}}</div>
<div class="meta">{{Meta}}</div>
''',
            'afmt': '''
{{FrontSide}}
<hr id="answer">
<div class="answer">{{Answer}}</div>
{{#Extra}}<div class="extra">{{Extra}}</div>{{/Extra}}
''',
        }],
        css=CARD_CSS)


def create_cloze_model(deck_name: str) -> genanki.Model:
    model_id = generate_id(f"cloze_v2_{deck_name}")

    return genanki.Model(
        model_id,
        f'{deck_name} Cloze',
        model_type=genanki.Model.CLOZE,
        fields=[
            {'name': 'Text'},
            {'name': 'Meta'},
            {'name': 'Extra'},
        ],
        templates=[{
            'name': 'Cloze',
            'qfmt': '''
<div class="question">{{cloze:Text}}</div>
<div class="meta">{{Meta}}</div>
''',
            'afmt': '''
<div class="answer">{{cloze:Text}}</div>
{{#Extra}}<div class="extra">{{Extra}}</div>{{/Extra}}
<div class="meta">{{Meta}}</div>
''',
        }],
        css=CARD_CSS)


CARD_CSS = '''
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
.answer { margin-top: 15px; }
.meta {
    font-size: 12px;
    color: #888;
    text-transform: capitalize;
    margin-top: 8px;
}
.extra {
    font-size: 14px;
    color: #666;
    font-style: italic;
    margin-top: 10px;
    padding: 8px 12px;
    border-left: 3px solid #ddd;
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
'''


def convert_cloze_syntax(text: str) -> str:
    """Convert {{blanked term}} to Anki's {{c1::blanked term}} format."""
    counter = [0]

    def replacer(match):
        counter[0] += 1
        return f"{{{{c{counter[0]}::{match.group(1)}}}}}"

    return re.sub(r'\{\{([^}]+)\}\}', replacer, text)


def build_extra(card: dict) -> str:
    """Build extra info string from mnemonic, context, source_detail."""
    parts = []
    if card.get('mnemonic'):
        parts.append(card['mnemonic'])
    if card.get('source_detail'):
        parts.append(f"Source: {card['source_detail']}")
    return ' | '.join(parts)


def build_meta(card: dict) -> str:
    tier = card.get('tier', '')
    card_type = card.get('type', '')
    priority = card.get('priority', '')
    context = card.get('context', '')
    parts = [p for p in [context, tier, card_type, priority] if p]
    return ' · '.join(parts)


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


def create_note(basic_model, cloze_model, card: dict, topic: str) -> genanki.Note:
    meta = build_meta(card)
    extra = convert_backticks_to_html(build_extra(card))
    tags = build_tags(card, topic)

    if card.get('type') == 'cloze' and card.get('cloze_text'):
        cloze_text = convert_cloze_syntax(card['cloze_text'])
        cloze_text = convert_backticks_to_html(cloze_text)
        guid = genanki.guid_for(card['cloze_text'])
        return genanki.Note(
            model=cloze_model,
            fields=[cloze_text, meta, extra],
            tags=tags,
            guid=guid,
        )

    question = convert_backticks_to_html(card.get('question', ''))
    answer = convert_backticks_to_html(card.get('answer', ''))
    guid = genanki.guid_for(card.get('question', f"card_{card.get('id', '')}"))

    return genanki.Note(
        model=basic_model,
        fields=[question, answer, meta, extra],
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

    basic_model = create_basic_model(deck_name)
    cloze_model = create_cloze_model(deck_name)
    deck_id = generate_id(f"deck_{deck_name}")
    deck = genanki.Deck(deck_id, deck_name)

    cloze_count = 0
    basic_count = 0
    for card in cards:
        note = create_note(basic_model, cloze_model, card, topic)
        deck.add_note(note)
        if card.get('type') == 'cloze':
            cloze_count += 1
        else:
            basic_count += 1

    package = genanki.Package(deck)
    package.write_to_file(output_path)

    stats = data.get('stats', {})
    by_tier = stats.get('by_tier', {})
    by_priority = stats.get('by_priority', {})

    print(f"Exported {len(cards)} cards to {output_path}")
    print(f"  Basic: {basic_count}, Cloze: {cloze_count}")
    print(f"\nDeck: {deck_name}")
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

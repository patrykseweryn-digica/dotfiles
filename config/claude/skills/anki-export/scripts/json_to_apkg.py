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
    return int(hashlib.md5(seed.encode()).hexdigest()[:8], 16)


def convert_backticks_to_html(text: str) -> str:
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', text)


CARD_CSS = '''
@import url('https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@300;400;600&family=Source+Code+Pro&display=swap');

*, *::before, *::after { box-sizing: border-box; }

.card {
    --bg: linear-gradient(135deg, #f5e6d0 0%, #e8d0b8 30%, #dcc8b0 60%, #e8dcc8 100%);
    --card-bg: rgba(235, 225, 205, 0.85);
    --card-border: rgba(235, 225, 205, 0.32);
    --card-shadow: 0 8px 32px rgba(100, 80, 50, 0.1);
    --text-q: #2a2018;
    --text-a: #2e2418;
    --meta-color: #8a7a64;
    --sep: linear-gradient(to right, transparent, rgba(200, 180, 150, 0.4), transparent);
    --code-bg: rgba(255, 255, 255, 0.3);
    --code-text: #8a6530;
    --code-border: rgba(200, 180, 150, 0.25);
    --extra-color: #6a5c48;
    --extra-border: rgba(235, 225, 205, 0.32);
    --explanation-color: #7a6a58;
    --glow: linear-gradient(to right, transparent 10%, rgba(255,255,255,0.5) 50%, transparent 90%);
    font-family: 'Source Sans 3', -apple-system, BlinkMacSystemFont, sans-serif;
    background:
        radial-gradient(ellipse 60% 40% at 80% 10%, rgba(220, 180, 130, 0.35) 0%, transparent 70%),
        radial-gradient(ellipse 50% 40% at 15% 90%, rgba(200, 160, 120, 0.25) 0%, transparent 70%),
        linear-gradient(135deg, #f5e6d0 0%, #e8d0b8 30%, #dcc8b0 60%, #e8dcc8 100%);
    padding: 12px;
    margin: 0;
    -webkit-font-smoothing: antialiased;
    text-align: center;
}

/* Glass card container */
.glass {
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 16px;
    padding: 18px;
    box-shadow: var(--card-shadow);
    position: relative;
    overflow: hidden;
    max-width: 560px;
    width: 100%;
    margin: 0 auto;
    z-index: 1;
}

/* Backdrop blur for supporting browsers */
@supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
    .glass {
        background: rgba(235, 225, 205, 0.48);
        backdrop-filter: blur(20px);
        -webkit-backdrop-filter: blur(20px);
    }
}

/* Top edge glow */
.glass::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 1px;
    background: var(--glow);
}

.meta {
    font-size: 11px;
    font-weight: 300;
    color: var(--meta-color);
    margin-bottom: 12px;
    letter-spacing: 0.08em;
    text-transform: uppercase;
}

.question {
    font-size: 18px;
    font-weight: 600;
    line-height: 1.4;
    color: var(--text-q);
    overflow-wrap: break-word;
}

.separator {
    height: 1px;
    background: var(--sep);
    margin: 16px 0;
    border: none;
}

.answer {
    font-size: 19px;
    font-weight: 500;
    line-height: 1.5;
    color: var(--text-a);
    overflow-wrap: break-word;
}

code {
    font-family: 'Source Code Pro', monospace;
    font-size: 0.88em;
    background: var(--code-bg);
    color: var(--code-text);
    padding: 3px 9px;
    border-radius: 8px;
    border: 1px solid var(--code-border);
    word-break: break-all;
}

.answer ul {
    display: inline-block;
    margin: 6px 0 0 0;
    padding-left: 20px;
    text-align: left;
}

.answer li {
    margin: 2px 0;
}

.extra {
    display: inline-block;
    font-style: italic;
    font-size: 14px;
    color: var(--extra-color);
    opacity: 0.8;
    margin-top: 16px;
    line-height: 1.6;
    padding-left: 18px;
    border-left: 2px solid var(--extra-border);
    text-align: left;
}

.explanation {
    font-size: 17px;
    font-weight: 400;
    line-height: 1.6;
    color: var(--explanation-color);
    margin-top: 14px;
    overflow-wrap: break-word;
}

/* ── Dark mode: AnkiDroid / AnkiMobile ── */
.nightMode.card,
.night_mode .card {
    --card-bg: rgba(65, 58, 48, 0.85);
    --card-border: rgba(105, 95, 75, 0.2);
    --card-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
    --text-q: #dcd0b8;
    --text-a: #d8ccb4;
    --meta-color: #9a8a70;
    --sep: linear-gradient(to right, transparent, rgba(150, 130, 100, 0.3), transparent);
    --code-bg: rgba(85, 75, 55, 0.35);
    --code-text: #d4c090;
    --code-border: rgba(105, 95, 75, 0.2);
    --extra-color: #a89880;
    --extra-border: rgba(105, 95, 75, 0.2);
    --explanation-color: #b0a080;
    --glow: linear-gradient(to right, transparent 10%, rgba(255,255,255,0.08) 50%, transparent 90%);
    background:
        radial-gradient(ellipse 60% 40% at 80% 10%, rgba(100, 80, 50, 0.25) 0%, transparent 70%),
        radial-gradient(ellipse 50% 40% at 15% 90%, rgba(80, 65, 40, 0.2) 0%, transparent 70%),
        linear-gradient(135deg, #302a24 0%, #362e28 30%, #2e2822 60%, #342c26 100%);
}

.nightMode.card .glass,
.night_mode .card .glass {
    background: var(--card-bg);
}

@supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
    .nightMode.card .glass,
    .night_mode .card .glass {
        background: rgba(65, 58, 48, 0.5);
    }
}

/* ── Dark mode: Anki Desktop ── */
@media (prefers-color-scheme: dark) {
    .card {
        --card-bg: rgba(65, 58, 48, 0.85);
        --card-border: rgba(105, 95, 75, 0.2);
        --card-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
        --text-q: #dcd0b8;
        --text-a: #d8ccb4;
        --meta-color: #9a8a70;
        --sep: linear-gradient(to right, transparent, rgba(150, 130, 100, 0.3), transparent);
        --code-bg: rgba(85, 75, 55, 0.35);
        --code-text: #d4c090;
        --code-border: rgba(105, 95, 75, 0.2);
        --extra-color: #a89880;
        --extra-border: rgba(105, 95, 75, 0.2);
        --explanation-color: #b0a080;
        --glow: linear-gradient(to right, transparent 10%, rgba(255,255,255,0.08) 50%, transparent 90%);
        background:
            radial-gradient(ellipse 60% 40% at 80% 10%, rgba(100, 80, 50, 0.25) 0%, transparent 70%),
            radial-gradient(ellipse 50% 40% at 15% 90%, rgba(80, 65, 40, 0.2) 0%, transparent 70%),
            linear-gradient(135deg, #302a24 0%, #362e28 30%, #2e2822 60%, #342c26 100%);
    }

    .glass {
        background: var(--card-bg);
    }

    @supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
        .glass {
            background: rgba(65, 58, 48, 0.5);
        }
    }
}
'''

FRONT_TEMPLATE = '''
<div class="glass">
{{#Meta}}<div class="meta">{{Meta}}</div>{{/Meta}}
<div class="question">{{Question}}</div>
</div>
'''

BACK_TEMPLATE = '''
<div class="glass">
{{#Meta}}<div class="meta">{{Meta}}</div>{{/Meta}}
<div class="question">{{Question}}</div>
<div class="separator"></div>
<div class="answer">{{Answer}}</div>
{{#Explanation}}<div class="explanation">{{Explanation}}</div>{{/Explanation}}
{{#Extra}}<div class="extra">{{Extra}}</div>{{/Extra}}
</div>
'''


def create_model(deck_name: str) -> genanki.Model:
    model_id = generate_id(f"model_glass_v2_{deck_name}")

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
            'qfmt': FRONT_TEMPLATE,
            'afmt': BACK_TEMPLATE,
        }],
        css=CARD_CSS)


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

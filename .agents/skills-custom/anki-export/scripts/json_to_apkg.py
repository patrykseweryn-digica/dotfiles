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
@import url('https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@300;400;600&family=Source+Code+Pro:wght@400;500&display=swap');

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 100%; min-height: 100%; margin: 0; padding: 0; }

/* ── Light theme tokens ── */
.card {
    --surface: #f2e8da;
    --surface-warm: rgba(220, 190, 150, 0.35);
    --surface-warm-0: rgba(220, 190, 150, 0);
    --surface-cool: rgba(200, 175, 140, 0.18);
    --surface-cool-0: rgba(200, 175, 140, 0);
    --card-bg: rgba(255, 253, 250, 0.72);
    --card-blur-bg: rgba(255, 253, 250, 0.48);
    --card-border: rgba(255, 255, 255, 0.5);
    --card-shadow: 0 1px 3px rgba(100, 80, 50, 0.05), 0 8px 32px rgba(100, 80, 50, 0.07);
    --text-q: #1e1810;
    --text-a: #3a2e20;
    --text-muted: #8a7c68;
    --sep: rgba(180, 160, 130, 0.28);
    --sep-0: rgba(180, 160, 130, 0);
    --code-bg: rgba(160, 140, 110, 0.1);
    --code-text: #7a5c30;
    --code-border: rgba(160, 140, 110, 0.18);
    --extra-border: rgba(180, 160, 130, 0.3);
    --glow: rgba(255, 255, 255, 0.55);
    --glow-0: rgba(255, 255, 255, 0);

    font-family: 'Source Sans 3', -apple-system, BlinkMacSystemFont, sans-serif;

    /* Layout: top-aligned, full viewport, stable on answer reveal */
    width: 100%;
    min-height: 100vh;
    min-height: 100dvh;
    padding: 48px 16px 24px;
    display: flex;
    flex-direction: column;
    align-items: center;

    /* FIX: explicit color stops instead of transparent (prevents dark band artifacts) */
    background-color: var(--surface);
    background-image:
        radial-gradient(ellipse 80% 60% at 70% 12%, var(--surface-warm) 0%, var(--surface-warm-0) 70%),
        radial-gradient(ellipse 60% 50% at 25% 88%, var(--surface-cool) 0%, var(--surface-cool-0) 70%);

    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-align: center;
}

/* ── Glass card ── */
.glass {
    background: var(--card-bg);
    border: 1px solid var(--card-border);
    border-radius: 20px;
    padding: 28px 26px;
    box-shadow: var(--card-shadow);
    /* Viewport-based width: 75vw on mobile, capped at 560px on desktop */
    width: clamp(280px, 75vw, 560px);
    position: relative;
    overflow: hidden;
}

@supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
    .glass {
        background: var(--card-blur-bg);
        backdrop-filter: blur(24px) saturate(1.15);
        -webkit-backdrop-filter: blur(24px) saturate(1.15);
    }
}

/* Top edge highlight */
.glass::before {
    content: '';
    position: absolute;
    top: 0; left: 24px; right: 24px;
    height: 1px;
    background: linear-gradient(to right, var(--glow-0), var(--glow), var(--glow-0));
    border-radius: 1px;
}

/* ── Typography ── */
.meta {
    font-size: 0.6875rem;
    font-weight: 600;
    color: var(--text-muted);
    margin-bottom: 0.875rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    opacity: 0.72;
}

.question {
    font-size: 1.125rem;
    font-weight: 600;
    line-height: 1.4;
    color: var(--text-q);
    overflow-wrap: break-word;
    word-break: break-word;
}

.separator {
    height: 1px;
    background: linear-gradient(to right, var(--sep-0), var(--sep), var(--sep-0));
    margin: 1.25rem 0;
    border: none;
}

.answer {
    font-size: 1.3125rem;
    font-weight: 500;
    line-height: 1.5;
    color: var(--text-a);
    overflow-wrap: break-word;
    word-break: break-word;
}

.explanation {
    font-size: 0.9375rem;
    font-weight: 400;
    line-height: 1.65;
    color: var(--text-muted);
    margin-top: 1rem;
    overflow-wrap: break-word;
}

.extra {
    display: inline-block;
    font-style: italic;
    font-size: 0.8125rem;
    font-weight: 400;
    color: var(--text-muted);
    opacity: 0.7;
    margin-top: 1.125rem;
    line-height: 1.55;
    padding-left: 0.875rem;
    border-left: 2px solid var(--extra-border);
    text-align: left;
}

/* ── Code ── */
code {
    font-family: 'Source Code Pro', 'SF Mono', Menlo, monospace;
    font-size: 0.84em;
    font-weight: 400;
    background: var(--code-bg);
    color: var(--code-text);
    padding: 2px 8px;
    border-radius: 6px;
    border: 1px solid var(--code-border);
    word-break: break-all;
}

/* ── Lists ── */
.answer ul {
    display: inline-block;
    margin: 8px 0 0;
    padding-left: 20px;
    text-align: left;
}

.answer li { margin: 3px 0; }

/* ── Responsive: small screens ── */
@media (max-width: 480px) {
    .card { padding: 2rem 0.75rem 1rem; }
    .glass { padding: 1.375rem 1.125rem; border-radius: 1rem; }
    .question { font-size: 1.0625rem; }
    .answer { font-size: 1.1875rem; }
    .explanation { font-size: 0.875rem; }
}

/* ── Dark theme mixin (reused across selectors) ── */
.nightMode.card,
.night_mode .card {
    --surface: #1c1814;
    --surface-warm: rgba(80, 65, 42, 0.28);
    --surface-warm-0: rgba(80, 65, 42, 0);
    --surface-cool: rgba(60, 50, 35, 0.18);
    --surface-cool-0: rgba(60, 50, 35, 0);
    --card-bg: rgba(48, 42, 34, 0.82);
    --card-blur-bg: rgba(48, 42, 34, 0.5);
    --card-border: rgba(85, 75, 58, 0.22);
    --card-shadow: 0 1px 3px rgba(0, 0, 0, 0.12), 0 8px 32px rgba(0, 0, 0, 0.18);
    --text-q: #e0d6c8;
    --text-a: #ccc0ac;
    --text-muted: #8a7e6c;
    --sep: rgba(120, 105, 78, 0.28);
    --sep-0: rgba(120, 105, 78, 0);
    --code-bg: rgba(85, 74, 55, 0.28);
    --code-text: #d4be88;
    --code-border: rgba(85, 74, 55, 0.28);
    --extra-border: rgba(100, 88, 65, 0.28);
    --glow: rgba(255, 255, 255, 0.05);
    --glow-0: rgba(255, 255, 255, 0);

    background-color: var(--surface);
    background-image:
        radial-gradient(ellipse 80% 60% at 70% 12%, var(--surface-warm) 0%, var(--surface-warm-0) 70%),
        radial-gradient(ellipse 60% 50% at 25% 88%, var(--surface-cool) 0%, var(--surface-cool-0) 70%);
}

.nightMode.card .glass,
.night_mode .card .glass {
    background: var(--card-bg);
}

@supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
    .nightMode.card .glass,
    .night_mode .card .glass {
        background: var(--card-blur-bg);
    }
}

/* Anki Desktop dark mode */
@media (prefers-color-scheme: dark) {
    .card {
        --surface: #1c1814;
        --surface-warm: rgba(80, 65, 42, 0.28);
        --surface-warm-0: rgba(80, 65, 42, 0);
        --surface-cool: rgba(60, 50, 35, 0.18);
        --surface-cool-0: rgba(60, 50, 35, 0);
        --card-bg: rgba(48, 42, 34, 0.82);
        --card-blur-bg: rgba(48, 42, 34, 0.5);
        --card-border: rgba(85, 75, 58, 0.22);
        --card-shadow: 0 1px 3px rgba(0, 0, 0, 0.12), 0 8px 32px rgba(0, 0, 0, 0.18);
        --text-q: #e0d6c8;
        --text-a: #ccc0ac;
        --text-muted: #8a7e6c;
        --sep: rgba(120, 105, 78, 0.28);
        --sep-0: rgba(120, 105, 78, 0);
        --code-bg: rgba(85, 74, 55, 0.28);
        --code-text: #d4be88;
        --code-border: rgba(85, 74, 55, 0.28);
        --extra-border: rgba(100, 88, 65, 0.28);
        --glow: rgba(255, 255, 255, 0.05);
        --glow-0: rgba(255, 255, 255, 0);

        background-color: var(--surface);
        background-image:
            radial-gradient(ellipse 80% 60% at 70% 12%, var(--surface-warm) 0%, var(--surface-warm-0) 70%),
            radial-gradient(ellipse 60% 50% at 25% 88%, var(--surface-cool) 0%, var(--surface-cool-0) 70%);
    }

    .glass { background: var(--card-bg); }

    @supports ((-webkit-backdrop-filter: blur(1px)) or (backdrop-filter: blur(1px))) {
        .glass { background: var(--card-blur-bg); }
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

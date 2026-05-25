---
name: flashcards
description: "Generate atomic flashcards from text, files, or URLs; JSON output; depth controls."
argument-hint: "[content or file path or URL] [--depth low|medium|high] [--pages 1-10] [--lang pl|en|source|...]"
---

# Flashcard Generator

Generate ultra-atomic flashcards as self-contained learning paths using Wozniak's knowledge formulation principles. Each card = one fact. More simple cards > fewer complex ones.

## Input Detection

Detect input type:
1. **File path**: starts with `/`, `./`, `~`, or common extensions → read the file using the agent's available file-reading capability
   - For PDFs >10 pages: ask user which pages to focus on, or use `--pages 1-10` argument
2. **URL**: starts with `http://` or `https://` → fetch the page using the agent's available web-reading capability
3. **Raw text**: everything else → process directly

## Agent Compatibility

Do not depend on specific host tool names. Use whatever equivalent capabilities the current agent provides for reading files, fetching URLs, and asking the user for clarification.

## Output Language

Default to Polish (`pl`). If the user explicitly requests another language with `--lang` or plain language instructions, use that language. Use `--lang source` only when the user wants cards in the source material's language.

Examples below use English placeholders only. Actual `question`, `answer`, `explanation`, and `mnemonic` fields must follow the selected output language.

Metadata values such as `topic` and `context` may remain English for stable filtering. Keep `source_detail` in the source's own section/heading wording when available.

## Card Types

| Type | Tier | Purpose |
|------|------|---------|
| **Atomic** | Foundational | Single fact/definition. Q: What is X? |
| **Conceptual** | Intermediate | Why/how something works. Q: Why does X...? |
| **Comparison** | Intermediate | Distinguish exactly TWO similar concepts. Q: How does X differ from Y? Never compare 3+ items — decompose into pairwise. |
| **Reverse** | Any | Same fact, opposite direction. Active: "What does X do?" → Passive: "What achieves Y?" |
| **Application** | Advanced | Realistic scenario. Q: How would you use X to...? |
| **Synthesis** | Advanced | Decision-making. Q: When would you choose X over Y? |

## Card Style

Style means the card's learning/wording style, not visual styling. Do not generate Anki CSS, note templates, fonts, colors, or deck styling unless the user explicitly asks for export styling.

Use these values in the optional `style` field:

| Style | Use when | Shape |
|-------|----------|-------|
| `minimal` | Default for atomic/reverse facts | Direct recall, shortest viable wording |
| `contrastive` | Concepts are easy to confuse | Names both concepts and tests the difference |
| `scenario` | Application/synthesis card | Concrete situation, learner chooses action |
| `consequence` | Failure modes or surprising outcomes matter | "What happens if X fails?" framing |
| `mnemonic` | Abstract or hard-to-visualize concept | Includes a `mnemonic` field |

Default to `minimal`. Use `contrastive` whenever interference risk is detected. Use `scenario` only when the question gives enough context to answer without guessing.

## Workflow

### Phase 1: Concept Extraction

1. Parse input (detect type, fetch content if needed)
2. Identify key concepts using 80/20 filter
3. **Aggressive decomposition**: any concept with multiple facets → multiple cards. "X has 3 parts: A, B, C" → at minimum 3 cards (one per part) + optionally "how many parts does X have?" Comparisons like "X vs Y vs Z" → separate cards per item + pairwise difference cards. Never compare more than 2 items on one card.
4. **Order basics→advanced**: arrange concepts so foundational ones come first - cards should work as a self-contained learning path even for someone encountering the material for the first time
5. **Detect interference**: flag concepts that are similar and could be confused with each other
6. **Assign priorities**: P1 (must-know), P2 (should-know), P3 (nice-to-know)
7. Determine output language: explicit user choice wins; otherwise use Polish (`pl`).
8. For short, unambiguous inputs likely to produce ≤10 cards, skip approval and proceed directly to Phase 2.
9. For URLs, PDFs, long text, ambiguous scope, or outputs likely >10 cards, present learning path outline:

```
## Learning Path

Found N concepts, ordered basics→advanced:

1. **[Concept A]** (P1) - X cards
   - atomic: definition of A
   - atomic: key property of A
   - reverse: what produces A

2. **[Concept B]** (P1) - X cards
   ⚠️ Similar to Concept A - cards include disambiguation
   - atomic: definition of B
   - comparison: B vs A

3. **[Concept C]** (P2) - X cards
   - requires: Concept A
   - application: using C in [context]

**Depth: medium | Language: pl | ~N cards (P1: X, P2: Y, P3: Z)**

Proceed? Or adjust?
```

10. Ask the user for approval or adjustments using the agent's available interaction mechanism, including language changes

### Phase 2: Card Generation

After approval, generate cards following quality rules below. Output JSON:

```json
{
  "topic": "Topic name derived from content",
  "source": "file path | URL | 'pasted text'",
  "language": "pl",
  "cards": [
    {
      "id": 1,
      "tier": "foundational",
      "type": "atomic",
      "style": "minimal",
      "priority": "P1",
      "question": "What is [concept]?",
      "answer": "Concise definition.",
      "explanation": "Optional 1-3 sentence elaboration of the answer — context, why it works, or common traps.",
      "context": "[Topic area]",
      "source_detail": "Section 2.1",
      "mnemonic": "Think of X as...",
      "related": [2, 5]
    },
    {
      "id": 2,
      "tier": "foundational",
      "type": "reverse",
      "style": "minimal",
      "priority": "P1",
      "question": "What technique achieves [Y]?",
      "answer": "[Concept X].",
      "related": [1]
    }
  ],
  "stats": {
    "total": 15,
    "by_tier": { "foundational": 6, "intermediate": 5, "advanced": 4 },
    "by_priority": { "P1": 7, "P2": 5, "P3": 3 }
  }
}
```

### Card field reference

| Field | Required? | Description |
|-------|----------|-------------|
| `id` | required | Sequential, in learning-path order |
| `tier` | required | foundational / intermediate / advanced |
| `type` | required | atomic / conceptual / comparison / reverse / application / synthesis |
| `style` | required | minimal / contrastive / scenario / consequence / mnemonic. Learning/wording style only; not visual styling |
| `priority` | required | P1 (must-know) / P2 (should-know) / P3 (nice-to-know) |
| `question` | required | The question |
| `answer` | required | The answer (target: 5-15 words, max: ~20 words). If the answer enumerates multiple distinct items (e.g. listing all values of a property), format as HTML: `"<ul><li>item1</li><li>item2</li><li>item3</li></ul>"`. Do NOT use this format when a comma-separated phrase reads naturally as a single unit. |
| `explanation` | optional | 1–3 sentence elaboration of the answer: background context, mechanism, or common pitfall |
| `context` | conditional | `[Topic]` tag to disambiguate ambiguous questions (e.g. `[Networking]`, `[Python]`) |
| `source_detail` | conditional | Section/heading reference when source material has clear structure |
| `mnemonic` | conditional | Imagery hint, analogy, or mnemonic device for abstract concepts |
| `related` | optional | IDs of genuinely related cards: active/reverse pairs, prerequisites, comparisons, or interference risks |

## Quality Rules (Wozniak-aligned)

### P1 Rules - always enforce

1. **Ultra-atomic**: one FACT per card, not one concept. If the answer contains "and", a comma-separated list, or multiple sentences → split into separate cards. Target answer: 5-15 words. Hard max: ~20 words. If you need more words, the card is testing too much.
2. **Aggressive decomposition**: any concept with multiple facets → multiple cards. "X has 3 parts: A, B, C" → at minimum 3 cards (one per part) + optionally "how many parts does X have?" Never present a list as a single card. Never compare more than 2 items on one card — decompose into pairwise comparisons.
3. **Split test**: before finalizing any card, ask: "Does this answer contain two facts that could be tested independently?" If yes → split. "X does A, and also B" is always two cards.
4. **Answer brevity**: strip every answer to minimum viable words. No filler phrases ("It is used to...", "This refers to...", "The mechanism that..."). Prefer fragments over full sentences. Not "The cascade is the mechanism CSS uses to resolve conflicts" but "CSS's conflict-resolution mechanism."
5. **Combat interference**: when two concepts are similar (terms, dates, processes), add distinguishing context, contrastive examples, or explicit comparison cards. Ask: "Could a learner confuse this with another card?"
6. **Redundancy for key concepts**: generate active ("What does X do?") and passive/reverse ("What achieves Y?") cards according to the selected depth - same fact, different angles
7. **Vivid framing**: use surprising facts, real consequences ("What happens if X fails?"), dramatic examples. Engage emotions - a card that makes you feel something is easier to remember
8. **Basics-first ordering**: card IDs reflect learning order. Foundational cards come before cards that depend on them. The card sequence should work as a standalone learning path

### P2 Rules - apply when natural

9. **Imagery/mnemonics**: for abstract or hard-to-visualize concepts, add a `mnemonic` field with an analogy, visual image, or memory device
10. **Explanations**: generate `explanation` for foundational/conceptual cards where the answer alone could be opaque; skip for reverse/application cards where the answer is self-sufficient
11. **Context cues**: add `context` tag when the question would be ambiguous without topic context
12. **Source references**: include `source_detail` with section/heading when the source material has clear structure

### P3 Rules - occasional use

13. **Date stamping**: for volatile/time-sensitive knowledge (tech versions, statistics, policies), prepend "As of [year]:" to the answer
14. **Recall over recognition**: questions force active recall, never multiple choice

## References

For detailed atomicity examples and a sample interaction, read `references/examples.md` when behavior is ambiguous, card quality drifts, or the user asks for examples.

## Depth Levels

User selects depth with `--depth low|medium|high` (default: medium).

| Depth | Coverage | Reverse cards |
|-------|----------|---------------|
| **low** | P1 concepts only. Minimum viable coverage. | Only for the most critical P1 facts |
| **medium** | P1 + P2 concepts. Comparison cards where interference risk exists. | Yes for P1 facts |
| **high** | All priorities. Multiple angles per P1 fact. Mnemonics for abstract concepts. Thorough interference coverage. | Yes for P1 + P2 facts |

Decide actual card count based on content complexity and depth. No fixed ranges — a simple topic at medium might produce 8 cards; a dense topic at medium might produce 40. Depth controls coverage and redundancy, including reverse-card generation, not an arbitrary number.

### Phase 2 Validation (before outputting JSON)

Before writing the final JSON, run this guard check:

1. **Answer presence**: every card MUST have a non-empty `answer` field. If any card is missing `answer`, generate the answer before outputting — never output a card without one.
2. **Report**: if any violations were found and fixed, append a brief note after the JSON block: `⚠️ Fixed N cards missing answers before output.`

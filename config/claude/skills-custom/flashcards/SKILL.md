---
name: flashcards
description: Generate ultra-atomic learning flashcards from text, files, or URLs. Use when user wants to create flashcards, study cards, quiz questions, or learning materials. Applies Wozniak's 20 rules of knowledge formulation - cards form self-contained learning paths ordered basics→advanced. Each card tests exactly one fact with short answers (5-15 words).
argument-hint: "[content or file path or URL] [--depth low|medium|high] [--pages 1-10]"
allowed-tools: Read, WebFetch, AskUserQuestion
---

# Flashcard Generator

Generate ultra-atomic flashcards as self-contained learning paths using Wozniak's knowledge formulation principles. Each card = one fact. More simple cards > fewer complex ones.

## Input Detection

Detect input type:
1. **File path**: starts with `/`, `./`, `~`, or common extensions → use Read tool
   - For PDFs >10 pages: ask user which pages to focus on, or use `--pages 1-10` argument
2. **URL**: starts with `http://` or `https://` → use WebFetch tool
3. **Raw text**: everything else → process directly

## Card Types

| Type | Tier | Purpose |
|------|------|---------|
| **Atomic** | Foundational | Single fact/definition. Q: What is X? |
| **Conceptual** | Intermediate | Why/how something works. Q: Why does X...? |
| **Comparison** | Intermediate | Distinguish exactly TWO similar concepts. Q: How does X differ from Y? Never compare 3+ items — decompose into pairwise. |
| **Reverse** | Any | Same fact, opposite direction. Active: "What does X do?" → Passive: "What achieves Y?" |
| **Application** | Advanced | Realistic scenario. Q: How would you use X to...? |
| **Synthesis** | Advanced | Decision-making. Q: When would you choose X over Y? |

## Workflow

### Phase 1: Concept Extraction

1. Parse input (detect type, fetch content if needed)
2. Identify key concepts using 80/20 filter
3. **Aggressive decomposition**: any concept with multiple facets → multiple cards. "X has 3 parts: A, B, C" → at minimum 3 cards (one per part) + optionally "how many parts does X have?" Comparisons like "X vs Y vs Z" → separate cards per item + pairwise difference cards. Never compare more than 2 items on one card.
4. **Order basics→advanced**: arrange concepts so foundational ones come first - cards should work as a self-contained learning path even for someone encountering the material for the first time
5. **Detect interference**: flag concepts that are similar and could be confused with each other
6. **Assign priorities**: P1 (must-know), P2 (should-know), P3 (nice-to-know)
7. Present learning path outline:

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

**Depth: medium | ~N cards (P1: X, P2: Y, P3: Z)**

Proceed? Or adjust?
```

8. Use AskUserQuestion to get approval or adjustments

### Phase 2: Card Generation

After approval, generate cards following quality rules below. Output JSON:

```json
{
  "topic": "Topic name derived from content",
  "source": "file path | URL | 'pasted text'",
  "cards": [
    {
      "id": 1,
      "tier": "foundational",
      "type": "atomic",
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

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Sequential, in learning-path order |
| `tier` | yes | foundational / intermediate / advanced |
| `type` | yes | atomic / conceptual / comparison / reverse / application / synthesis |
| `priority` | yes | P1 (must-know) / P2 (should-know) / P3 (nice-to-know) |
| `question` | yes | The question |
| `answer` | yes | The answer (target: 5-15 words, max: ~20 words). If the answer enumerates multiple distinct items (e.g. listing all values of a property), format as HTML: `"<ul><li>item1</li><li>item2</li><li>item3</li></ul>"`. Do NOT use this format when a comma-separated phrase reads naturally as a single unit. |
| `explanation` | optional | 1–3 sentence elaboration of the answer: background context, mechanism, or common pitfall |
| `context` | when ambiguous | `[Topic]` tag to disambiguate (e.g. `[Networking]`, `[Python]`) |
| `source_detail` | when available | Section/heading reference from source material |
| `mnemonic` | for abstract concepts | Imagery hint, analogy, or mnemonic device |
| `related` | yes | IDs of related cards |

## Quality Rules (Wozniak-aligned)

### P1 Rules - always enforce

1. **Ultra-atomic**: one FACT per card, not one concept. If the answer contains "and", a comma-separated list, or multiple sentences → split into separate cards. Target answer: 5-15 words. Hard max: ~20 words. If you need more words, the card is testing too much.
2. **Aggressive decomposition**: any concept with multiple facets → multiple cards. "X has 3 parts: A, B, C" → at minimum 3 cards (one per part) + optionally "how many parts does X have?" Never present a list as a single card. Never compare more than 2 items on one card — decompose into pairwise comparisons.
3. **Split test**: before finalizing any card, ask: "Does this answer contain two facts that could be tested independently?" If yes → split. "X does A, and also B" is always two cards.
4. **Answer brevity**: strip every answer to minimum viable words. No filler phrases ("It is used to...", "This refers to...", "The mechanism that..."). Prefer fragments over full sentences. Not "The cascade is the mechanism CSS uses to resolve conflicts" but "CSS's conflict-resolution mechanism."
5. **Combat interference**: when two concepts are similar (terms, dates, processes), add distinguishing context, contrastive examples, or explicit comparison cards. Ask: "Could a learner confuse this with another card?"
6. **Redundancy for key concepts**: for P1 items, generate both active ("What does X do?") and passive/reverse ("What achieves Y?") cards - same fact, different angles
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

## Atomicity Examples

### BAD: Multi-fact answer
Q: What is the CSS cascade?
A: The mechanism CSS uses to resolve conflicts when multiple rules target the same element. It checks importance (!important), then specificity, then source order (last wins).

### GOOD: Decomposed into atomic cards
1. Q: What does the CSS cascade do? → A: Resolves conflicts when multiple rules target the same element.
2. Q: How many cascade resolution steps are there? → A: Three.
3. Q: What does the cascade check first? → A: Importance (!important declarations).
4. Q: What does the cascade check after importance? → A: Specificity.
5. Q: What is the cascade's final tiebreaker? → A: Source order — last rule wins.

### BAD: Packed 4-way comparison
Q: inherit vs initial vs revert vs unset?
A: inherit copies parent value, initial resets to spec default, revert rolls back to user-agent style, unset acts as inherit for inherited props and initial for others.

### GOOD: One card per value + pairwise comparisons
1. Q: What does `inherit` do? → A: Copies the parent element's computed value.
2. Q: What does `initial` do? → A: Resets to the CSS spec default.
3. Q: What does `revert` do? → A: Rolls back to the browser's default stylesheet.
4. Q: What does `unset` do on inherited properties? → A: Acts as `inherit`.
5. Q: What does `unset` do on non-inherited properties? → A: Acts as `initial`.
6. Q: How does `initial` differ from `revert`? → A: `initial` = spec default; `revert` = browser default.

### BAD: Hidden multi-concept
Q: What scoring system determines which CSS selector wins?
A: The 4-slot specificity system: (inline, ID, class, element). Higher slots always outrank lower — one ID beats any number of classes.

### GOOD: One slot per card
1. Q: How many slots does CSS specificity have? → A: Four.
2. Q: What is specificity slot 1 (highest)? → A: Inline styles.
3. Q: What is specificity slot 2? → A: ID selectors.
4. Q: What is specificity slot 3? → A: Classes, attributes, pseudo-classes.
5. Q: What is specificity slot 4 (lowest)? → A: Elements, pseudo-elements.
6. Q: Can many class selectors outrank one ID? → A: No — a higher slot always beats any count in lower slots.

## Depth Levels

User selects depth with `--depth low|medium|high` (default: medium).

| Depth | Coverage | Reverse cards |
|-------|----------|---------------|
| **low** | P1 concepts only. Minimum viable coverage. | Only for the most critical P1 facts |
| **medium** | P1 + P2 concepts. Comparison cards where interference risk exists. | Yes for P1 facts |
| **high** | All priorities. Multiple angles per P1 fact. Mnemonics for abstract concepts. Thorough interference coverage. | Yes for P1 + P2 facts |

Claude decides actual card count based on content complexity and depth. No fixed ranges — a simple topic at medium might produce 8 cards; a dense topic at medium might produce 40. Depth controls coverage and redundancy, not an arbitrary number.

## Example Interaction

**User**: `/flashcards https://example.com/react-hooks-guide`

**Phase 1 Response**:
```
## Learning Path

Found 4 concepts from "React Hooks Guide", ordered basics→advanced:

1. **useState** (P1) - 4 cards
   - atomic: what useState returns
   - atomic: useState syntax
   - reverse: how to add state to a function component
   - application: managing form input state

2. **useEffect** (P1) - 5 cards
   ⚠️ Similar to useState lifecycle - cards include disambiguation
   - atomic: what useEffect does
   - atomic: dependency array syntax
   - conceptual: why effects run after render
   - comparison: useEffect vs componentDidMount/didUpdate
   - reverse: how to run code on mount only

3. **Rules of Hooks** (P1) - 4 cards
   - requires: useState, useEffect
   - atomic: how many rules of hooks exist
   - atomic: rule 1 — top-level only
   - atomic: rule 2 — React functions only
   - conceptual: why top-level only

4. **Custom Hooks** (P2) - 3 cards
   - requires: useState, useEffect, Rules of Hooks
   - atomic: what makes a function a custom hook
   - application: extracting reusable stateful logic
   - reverse: what pattern extracts shared hook logic

**Depth: medium | ~16 cards (P1: 13, P2: 3, P3: 0)**

Proceed? Or adjust?
```

**User**: "proceed" or "more on useEffect" or "make Rules of Hooks P2"

**Phase 2**: Generate and output JSON with all fields populated

### Phase 2 Validation (before outputting JSON)

Before writing the final JSON, run this guard check:

1. **Answer presence**: every card where `type` ≠ `"cloze"` MUST have a non-empty `answer` field. If any card is missing `answer`, generate the answer before outputting — never output a card without one.
2. **Cloze completeness**: every card where `type` = `"cloze"` MUST have a non-empty `cloze_text` field with at least one `{{...}}` blank.
3. **Report**: if any violations were found and fixed, append a brief note after the JSON block: `⚠️ Fixed N cards missing answers before output.`

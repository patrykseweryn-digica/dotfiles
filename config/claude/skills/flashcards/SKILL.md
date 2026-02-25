---
name: flashcards
description: Generate learning flashcards from text, files, or URLs. Use when user wants to create flashcards, study cards, quiz questions, or learning materials. Applies Wozniak's 20 rules of knowledge formulation - cards form self-contained learning paths ordered basics→advanced.
argument-hint: "[content or file path or URL] [--count N] [--pages 1-10]"
allowed-tools: Read, WebFetch, AskUserQuestion
---

# Flashcard Generator

Generate high-quality flashcards as self-contained learning paths using Wozniak's knowledge formulation principles.

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
| **Cloze** | Foundational/Intermediate | Fill-in-the-blank. `{{blanked term}}` in sentence |
| **Conceptual** | Intermediate | Why/how something works. Q: Why does X...? |
| **Comparison** | Intermediate | Distinguish similar concepts. Q: How does X differ from Y? |
| **Reverse** | Any | Same fact, opposite direction. Active: "What does X do?" → Passive: "What achieves Y?" |
| **Application** | Advanced | Realistic scenario. Q: How would you use X to...? |
| **Synthesis** | Advanced | Decision-making. Q: When would you choose X over Y? |

## Workflow

### Phase 1: Concept Extraction

1. Parse input (detect type, fetch content if needed)
2. Identify key concepts using 80/20 filter
3. **Decompose lists/sets**: any enumeration in source must be broken into individual atomic cards - never present a list as a single card
4. **Order basics→advanced**: arrange concepts so foundational ones come first - cards should work as a self-contained learning path even for someone encountering the material for the first time
5. **Detect interference**: flag concepts that are similar and could be confused with each other
6. **Assign priorities**: P1 (must-know), P2 (should-know), P3 (nice-to-know)
7. Present learning path outline:

```
## Learning Path

Found N concepts, ordered basics→advanced:

1. **[Concept A]** (P1) - X cards
   - atomic: definition of A
   - cloze: key property of A
   - reverse: what produces A

2. **[Concept B]** (P1) - X cards
   ⚠️ Similar to Concept A - cards include disambiguation
   - atomic: definition of B
   - comparison: B vs A

3. **[Concept C]** (P2) - X cards
   - requires: Concept A
   - application: using C in [context]

**Total: ~N cards (P1: X, P2: Y, P3: Z)**

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
      "context": "[Topic area]",
      "source_detail": "Section 2.1",
      "mnemonic": "Think of X as...",
      "related": [2, 5]
    },
    {
      "id": 2,
      "tier": "foundational",
      "type": "cloze",
      "priority": "P1",
      "cloze_text": "The primary function of X is {{doing Y}} which enables Z.",
      "context": "[Topic area]",
      "related": [1]
    },
    {
      "id": 3,
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
| `type` | yes | atomic / cloze / conceptual / comparison / reverse / application / synthesis |
| `priority` | yes | P1 (must-know) / P2 (should-know) / P3 (nice-to-know) |
| `question` | yes* | The question (*not used for cloze type) |
| `answer` | yes* | The answer (*not used for cloze type) |
| `cloze_text` | cloze only | Sentence with `{{blanked term}}` |
| `context` | when ambiguous | `[Topic]` tag to disambiguate (e.g. `[Networking]`, `[Python]`) |
| `source_detail` | when available | Section/heading reference from source material |
| `mnemonic` | for abstract concepts | Imagery hint, analogy, or mnemonic device |
| `related` | yes | IDs of related cards |

## Quality Rules (Wozniak-aligned)

### P1 Rules - always enforce

1. **Atomic**: one concept per card, no compound questions
2. **No sets/enumerations**: never put a list in one card. Decompose into individual atomic or cloze cards. If source says "3 types of X: A, B, C" → create separate cards for each type
3. **Combat interference**: when two concepts are similar (terms, dates, processes), add distinguishing context, contrastive examples, or explicit comparison cards. Ask: "Could a learner confuse this with another card?"
4. **Redundancy for key concepts**: for P1 items, generate both active ("What does X do?") and passive/reverse ("What achieves Y?") cards - same fact, different angles
5. **Wording optimization**: reduce every card to its most compact, elegant form. Every word must earn its place. Like simplifying a math equation - remove everything that doesn't add meaning
6. **Vivid framing**: use surprising facts, real consequences ("What happens if X fails?"), dramatic examples. Engage emotions - a card that makes you feel something is easier to remember
7. **Basics-first ordering**: card IDs reflect learning order. Foundational cards come before cards that depend on them. The card sequence should work as a standalone learning path

### P2 Rules - apply when natural

8. **Cloze preference**: for definitions and factual statements, prefer cloze format over plain Q&A when the fill-in-the-blank feels natural
9. **Imagery/mnemonics**: for abstract or hard-to-visualize concepts, add a `mnemonic` field with an analogy, visual image, or memory device
10. **Context cues**: add `context` tag when the question would be ambiguous without topic context
11. **Source references**: include `source_detail` with section/heading when the source material has clear structure

### P3 Rules - occasional use

12. **Date stamping**: for volatile/time-sensitive knowledge (tech versions, statistics, policies), prepend "As of [year]:" to the answer
13. **Recall over recognition**: questions force active recall, never multiple choice

## Default Card Count

- Short content (<500 words): 5-10 cards
- Medium content (500-2000 words): 12-20 cards
- Long content (>2000 words): 20-35 cards
- User can override with `--count N`
- Counts are higher than plain Q&A because redundancy (reverse cards) and list decomposition increase card count

## Example Interaction

**User**: `/flashcards https://example.com/react-hooks-guide`

**Phase 1 Response**:
```
## Learning Path

Found 4 concepts from "React Hooks Guide", ordered basics→advanced:

1. **useState** (P1) - 4 cards
   - atomic: what useState returns
   - cloze: useState syntax
   - reverse: how to add state to a function component
   - application: managing form input state

2. **useEffect** (P1) - 5 cards
   ⚠️ Similar to useState lifecycle - cards include disambiguation
   - atomic: what useEffect does
   - cloze: dependency array syntax
   - conceptual: why effects run after render
   - comparison: useEffect vs componentDidMount/didUpdate
   - reverse: how to run code on mount only

3. **Rules of Hooks** (P1) - 3 cards
   - requires: useState, useEffect
   - atomic: the two rules
   - conceptual: why top-level only (consequence framing)
   - cloze: where hooks can/cannot be called

4. **Custom Hooks** (P2) - 3 cards
   - requires: useState, useEffect, Rules of Hooks
   - atomic: what makes a function a custom hook
   - application: extracting reusable stateful logic
   - reverse: what pattern extracts shared hook logic

**Total: ~15 cards (P1: 12, P2: 3, P3: 0)**

Proceed? Or adjust?
```

**User**: "proceed" or "more on useEffect" or "make Rules of Hooks P2"

**Phase 2**: Generate and output JSON with all fields populated

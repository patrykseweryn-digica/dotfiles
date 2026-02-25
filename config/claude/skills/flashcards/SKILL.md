---
name: flashcards
description: Generate learning flashcards from text, files, or URLs. Use when user wants to create flashcards, study cards, quiz questions, or learning materials.
argument-hint: "[content or file path or URL] [--count N] [--pages 1-10]"
allowed-tools: Read, WebFetch, AskUserQuestion
---

# Flashcard Generator

Generate high-quality learning flashcards from any content using the 80/20 principle.

## Input Detection

Detect input type:
1. **File path**: starts with `/`, `./`, `~`, or common extensions (.md, .py, .js, .txt, .pdf, etc.) → use Read tool
   - For PDFs >10 pages: ask user which pages to focus on, or use `--pages 1-10` argument
2. **URL**: starts with `http://` or `https://` → use WebFetch tool
3. **Raw text**: everything else → process directly

## Card Types

| Type | Tier | Purpose |
|------|------|---------|
| **Atomic** | Foundational | Single fact/definition. Q: What is X? |
| **Conceptual** | Intermediate | Why/how something works. Q: Why does X...? |
| **Comparison** | Intermediate | Distinguish related concepts. Q: How does X differ from Y? |
| **Application** | Advanced | Use in realistic scenario. Q: How would you use X to...? |
| **Synthesis** | Advanced | Decision-making. Q: When would you choose X over Y? |

## Workflow

### Phase 1: Concept Extraction

1. Parse input (detect type, fetch content if needed)
2. Identify key concepts using 80/20 filter (focus on most impactful ~20%)
3. Present concept outline to user:

```
## Concept Outline

Found N key concepts:

1. **[Concept A]** - X cards planned
   - foundational: definition of A
   - application: using A in [context]

2. **[Concept B]** - X cards planned
   - foundational: what B is
   - conceptual: why B matters

3. **[Concept C]** - X cards planned
   - comparison: C vs A

**Total: ~N cards**

Proceed? Or adjust (e.g., "skip concept C", "more on A", "add comparison between A and B")
```

4. Use AskUserQuestion to get approval or adjustments
5. If user requests changes, update concept plan and re-present

### Phase 2: Card Generation

After approval, generate cards and output JSON:

```json
{
  "topic": "Topic name derived from content",
  "source": "file path | URL | 'pasted text'",
  "cards": [
    {
      "id": 1,
      "tier": "foundational",
      "type": "atomic",
      "question": "What is [concept]?",
      "answer": "Concise definition in 1-2 sentences max.",
      "related": [2, 5]
    }
  ],
  "stats": {
    "total": 12,
    "by_tier": {
      "foundational": 5,
      "intermediate": 4,
      "advanced": 3
    }
  }
}
```

## Quality Rules

1. **Atomic principle**: One concept per card, no compound questions
2. **Concise answers**: Max 2 sentences per answer
3. **Recall over recognition**: Questions should force active recall, not multiple choice
4. **Meaningful comparisons**: Only compare concepts that share real relationships
5. **Realistic applications**: Scenarios should be specific and practical
6. **Cross-references**: Link related cards via `related` field to show concept connections
7. **Tiered progression**: Start with foundational facts, build to applications

## Default Card Count

- Short content (<500 words): 5-8 cards
- Medium content (500-2000 words): 10-15 cards
- Long content (>2000 words): 15-25 cards
- User can override with `--count N`

## Example Interaction

**User**: `/flashcards https://example.com/react-hooks-guide`

**Phase 1 Response**:
```
## Concept Outline

Found 4 key concepts from "React Hooks Guide":

1. **useState** - 3 cards
   - foundational: what useState does
   - conceptual: why useState over class state
   - application: managing form state

2. **useEffect** - 3 cards
   - foundational: what useEffect does
   - conceptual: dependency array behavior
   - comparison: useEffect vs componentDidMount

3. **Custom Hooks** - 2 cards
   - foundational: what custom hooks are
   - application: extracting reusable logic

4. **Rules of Hooks** - 2 cards
   - foundational: the two rules
   - conceptual: why rules exist

**Total: ~10 cards**

Proceed? Or adjust?
```

**User**: "proceed" or "more on useEffect"

**Phase 2**: Generate and output JSON

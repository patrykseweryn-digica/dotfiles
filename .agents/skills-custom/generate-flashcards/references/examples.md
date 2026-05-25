# Flashcard Examples

Load this file when the skill behavior is ambiguous, when card atomicity drifts, or when the user asks for examples.

## Atomicity Examples

### BAD: Multi-fact answer
Q: What is the CSS cascade?
A: The mechanism CSS uses to resolve conflicts when multiple rules target the same element. It checks importance (!important), then specificity, then source order (last wins).

### GOOD: Decomposed into atomic cards
1. Q: What does the CSS cascade do? -> A: Resolves conflicts when multiple rules target the same element.
2. Q: How many cascade resolution steps are there? -> A: Three.
3. Q: What does the cascade check first? -> A: Importance (!important declarations).
4. Q: What does the cascade check after importance? -> A: Specificity.
5. Q: What is the cascade's final tiebreaker? -> A: Source order - last rule wins.

### BAD: Packed 4-way comparison
Q: inherit vs initial vs revert vs unset?
A: inherit copies parent value, initial resets to spec default, revert rolls back to user-agent style, unset acts as inherit for inherited props and initial for others.

### GOOD: One card per value + pairwise comparisons
1. Q: What does `inherit` do? -> A: Copies the parent element's computed value.
2. Q: What does `initial` do? -> A: Resets to the CSS spec default.
3. Q: What does `revert` do? -> A: Rolls back to the browser's default stylesheet.
4. Q: What does `unset` do on inherited properties? -> A: Acts as `inherit`.
5. Q: What does `unset` do on non-inherited properties? -> A: Acts as `initial`.
6. Q: How does `initial` differ from `revert`? -> A: `initial` = spec default; `revert` = browser default.

### BAD: Hidden multi-concept
Q: What scoring system determines which CSS selector wins?
A: The 4-slot specificity system: (inline, ID, class, element). Higher slots always outrank lower - one ID beats any number of classes.

### GOOD: One slot per card
1. Q: How many slots does CSS specificity have? -> A: Four.
2. Q: What is specificity slot 1 (highest)? -> A: Inline styles.
3. Q: What is specificity slot 2? -> A: ID selectors.
4. Q: What is specificity slot 3? -> A: Classes, attributes, pseudo-classes.
5. Q: What is specificity slot 4 (lowest)? -> A: Elements, pseudo-elements.
6. Q: Can many class selectors outrank one ID? -> A: No - a higher slot always beats any count in lower slots.

## Example Interaction

**User**: `/generate-flashcards https://example.com/react-hooks-guide`

**Phase 1 Response**:

```markdown
## Learning Path

Found 4 concepts from "React Hooks Guide", ordered basics->advanced:

1. **useState** (P1) - 4 cards
   - atomic: what useState returns
   - atomic: useState syntax
   - reverse: how to add state to a function component
   - application: managing form input state

2. **useEffect** (P1) - 5 cards
   - similar to useState lifecycle; cards include disambiguation
   - atomic: what useEffect does
   - atomic: dependency array syntax
   - conceptual: why effects run after render
   - comparison: useEffect vs componentDidMount/didUpdate
   - reverse: how to run code on mount only

3. **Rules of Hooks** (P1) - 4 cards
   - requires: useState, useEffect
   - atomic: how many rules of hooks exist
   - atomic: rule 1 - top-level only
   - atomic: rule 2 - React functions only
   - conceptual: why top-level only

4. **Custom Hooks** (P2) - 3 cards
   - requires: useState, useEffect, Rules of Hooks
   - atomic: what makes a function a custom hook
   - application: extracting reusable stateful logic
   - reverse: what pattern extracts shared hook logic

**Depth: medium | Language: pl | ~16 cards (P1: 13, P2: 3, P3: 0)**

Proceed? Or adjust?
```

**User**: "proceed" or "more on useEffect" or "make Rules of Hooks P2"

**Phase 2**: Generate and output JSON with all fields populated.

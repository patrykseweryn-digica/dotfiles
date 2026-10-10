---
name: show-the-change
description: >-
  Turns proposed changes and difficult explanations into concrete, verified
  before-and-after comparisons with a direct recommendation. Use when proposing
  code, UI, configuration, architecture, data, or process changes, when results
  are hard to picture, or when explanations remain unclear.
---

# Show the Change

Make the result concrete enough for a first-time reader to understand and
decide.

## Vocabulary

- **Before** means the real, verified code, UI, configuration, data, or process
  before the proposed change.
- **After** means the exact result the user will get after the proposed change.
- Use the user's language for both labels.

## When to use

- Use this skill automatically for changes the user must understand or approve.
- Use this skill when an explanation is difficult to picture.
- Use this skill immediately when the user says an explanation is unclear.
- Skip this skill for simple facts and trivial answers.

## Workflow

1. Inspect the real source before describing **Before**.
2. Lead with the practical result in one to three sentences.
3. Assume the reader sees the project and topic for the first time.
4. Define each necessary unfamiliar term in plain language.
5. Show **Before** and **After** in the clearest concrete form.
6. Give one direct recommendation and its reason.
7. Add benefits, costs, and risks only when they affect the decision.

## Choose the comparison

- For code, show small verified snippets from the affected files.
- For UI, show the current screen and a rendered proposal.
- Use Lavish for visual comparison when available and materially clearer.
- For configuration or data, show concrete values or rows.
- For a process, show the current steps and proposed steps.
- For architecture, show the affected flow and ownership.

Use side-by-side output when both versions stay readable. Otherwise, show
**Before** first and **After** second.

## Evidence boundary

Never invent **Before**. If inspection is impossible, name the missing
evidence.

Mark every substitute example as illustrative. Ask a question only when the
missing evidence blocks a safe recommendation.

## Plain language

- Match the user's language.
- Use short, grammatical sentences.
- Put one idea in each sentence.
- Use active voice and concrete verbs.
- Avoid unexplained jargon.
- Prefer a small example over an abstract description.

## Minimum response

```text
Result: <the practical outcome>

Before: <the verified current code, screen, value, or steps>

After: <the exact proposed code, screen, value, or steps>

Recommendation: <the choice and reason>
```

Add `Benefits`, `Costs`, or `Risks` only when useful.

## Illustrative examples

Code change:

```text
Before: client.py uses a 5-second timeout.
After: client.py uses a 10-second timeout.
Recommendation: Use 10 seconds because verified requests need up to 8 seconds.
Risk: A failed request can take 5 seconds longer.
```

UI change:

```text
Before: The Save button appears below the full form.
After: A rendered sticky bar keeps Save visible while scrolling.
Recommendation: Use the sticky bar because the form spans several screens.
```

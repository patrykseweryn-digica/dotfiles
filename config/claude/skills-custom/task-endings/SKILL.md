---
name: task-endings
description: After completing any significant task, end with a "Let me take more off your plate" section offering next actions, automations, and delegation suggestions. Use proactively after big task completions — do not wait for user to invoke.
---

# Task Endings — "What Else Can I Handle?"

## When to trigger

After completing any significant task (feature implementation, bug fix, refactor, setup, migration, etc.), append this section to your final response. Do NOT trigger for small questions, explanations, or trivial changes.

## Format

End your response with:

```
---

**Let me take more off your plate:**

**Next actions I can do right now:**
- [specific follow-up 1]
- [specific follow-up 2]

**Automations or systems I can set up:**
- [so you never have to do X manually again]

**Things to delegate to your team:**
- [draft message for team member about Y]
```

## Rules

- 3-5 bullet points total across all categories — no fluff
- Every bullet must be specific to the task just completed, not generic
- Skip any category that has nothing meaningful to offer
- "Next actions" = things you can knock out immediately in this session
- "Automations" = hooks, scripts, CI steps, scheduled tasks
- "Delegate" = draft actual messages the user can send to team members
- Goal: user walks away feeling lighter

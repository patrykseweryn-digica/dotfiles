---
name: kolbs-reflection
description: Guide the user through Justin Sung's Kolb's Experimental Cycle (Experience → Reflection → Abstraction → Experiment) with socratic challenge, hard gates on input quality, and persistence to the user's Obsidian vault. Use when user says "kolb", "zróbmy kolba", "reflection cycle", "chcę zreflektować", "marginal gain", "justin sung", or wants to deeply reflect on a learning/coding/work process to extract root-cause patterns and run targeted experiments. Also trigger when user says "chcę popracować nad procesem X" or "popraw mój proces nauki/kodowania" — suggest the skill before they ask.
---

# Kolb's Reflection

Guide the user through Justin Sung's adaptation of Kolb's Experimental Cycle. The output is a deeply reflective markdown note saved to the user's Obsidian vault, plus an updated experiment-tracking index.

## Non-negotiables

- **Always interactive.** Override any Auto Mode. Every step needs the user's own words. If you fill in answers from prior context, the cycle is worthless.
- **Polish session and output**, even when reflecting on coding. Technical terms (`merge conflict`, `refactor`) stay in English in-line.
- **Hard gate on Step 1.** Do not progress to Reflection until Experience passes all 4 criteria. Reframe the user back if they violate them.
- **Force-rank Step 4 to ≤3 experiments.** Extras go to `parking_lot` in frontmatter, never silently dropped.
- **Show the final note in chat before saving.** Wait for explicit user approval. This is the vault rule.
- **Socratic grilling on shallow answers.** Max 2-3 follow-ups per question; then accept and move on.

## Workflow

### 0. Bootstrap

1. Detect vault path: `~/Documents/just-stefan-things/` (mac) or `~/Documents/Obsidian/just-stefan-things/` (linux).
2. Read `Osiąganie swoich celów/Kolbs/_index.md` if it exists. Extract open experiments (status `open`).
3. If open experiments exist, list them: "Masz otwarte eksperymenty z poprzednich cykli: [...] — który teraz testujemy, czy zaczynamy nowy wątek?"
4. If user picks an experiment: pre-frame Experience as "jak poszło testowanie [X]?". Note `previous: [[YYYY-MM-DD-slug]]` in mind.
5. If no index or new thread: continue without `previous`.

### 1. Experience (HARD GATE)

Ask: "What experience do you want to reflect on?" (1 sentence ideal).

Then validate against 4 criteria. **Do not proceed until all 4 pass:**

- [ ] **Process-focused** — not the outcome ("test failed") but the process leading to it ("how I prepared for the test") or your reaction ("how I responded after seeing the score")
- [ ] **Specific** — one event, not "this whole week" or "all my code reviews"
- [ ] **Recent** — last few days ideal, max ~2 weeks
- [ ] **Concise** — fits in 1 sentence

If any fails, reframe with a question that pulls the user toward the missing dimension. Examples in `EXAMPLES.md`. Once it passes, also ask: **"What would a marginal gain look like here?"** (don't validate this — it primes the rest of the cycle).

### 2. Reflection

Ask these in order. Use socratic grilling (max 2-3 follow-ups) when answers are shallow, abstract, or jump to theory:

1. **Sequence of events, chronological** — concrete what-happened-when
2. **How did you feel? When?** — push for specifics, heightened emotions = signals
3. **Which aspects felt especially difficult? Which went well?**
4. **How did you respond to difficulties?** — *honestly*, including avoidance/retreat. Skip if no difficulties.
5. **Triggers** — what cues/signs/exposures made you feel/act this way? (external)
6. **Why do you think you acted that way?** — metacognitive, internal: emotions/thoughts driving behavior (distinct from triggers)

**Stuck-handling** (when user says "nie wiem" / "nic mi nie przychodzi"):
- Reframe the question from a different angle ("OK, co pomyślałeś tuż przed tym jak X?")
- Offer a pattern-priming example **from a different life domain** (never from their current situation — risk of suggestion)
- If still stuck after 2 reframes: log it as a self-awareness gap, move on. See `REFERENCE.md` "When user is stuck".

**Soft check-in at end of Step 2:** "Jesteśmy w połowie. Czujesz, że refleksja jest wystarczająco głęboka, by zbudować na niej Abstraction? Możemy też zapisać draft i wrócić."

### 3. Abstraction

Ask:

1. **What habits, beliefs, tendencies from your reflection explain why you acted that way?**
2. **Do you act/respond similarly in other parts of life?** (holistic impact)

**Critical check:** Every pattern named must be *supported by the reflection*. If the user theorizes ("I probably do this because of childhood..."), but nothing in their Reflection supports it — push back: "What in your reflection points to that? If nothing — we're theorizing, that's where cognitive bias creeps in." Accept "I don't have enough data points yet" as a legitimate answer.

### 4. Experiment

Ask: "List potential solutions and actions to experiment on."

Let the user dump all ideas first (can be 5-10). Then:

1. **Force-rank.** "We keep max 3. Which ones are (a) most actionable tomorrow morning, (b) most specific, (c) highest expected impact?"
2. **Make each one waking-up-tomorrow concrete.** Vague "I'll be more mindful" → "Before each debug session I write a 1-sentence hypothesis on paper".
3. **Optionally** suggest a deadline (1 week, 2 weeks) per experiment.
4. Extras → `parking_lot` array in frontmatter.

### 5. Synthesize and save

Build the note. Structure:

```markdown
---
date: YYYY-MM-DD
domain: <kodowanie|nauka|praca|osobiste|...>
previous: [[YYYY-MM-DD-slug]]    # only if continuing a thread
experiments:
  - text: "..."
    status: open
    deadline: YYYY-MM-DD          # optional
parking_lot:
  - "..."
tags: [kolb, <domain>]
---

# Kolb: <short title from Experience>

## TL;DR
**Experience:** <1 sentence>
**Patterns:** <2-3 bullets from Abstraction>
**Experiments:**
1. <experiment 1>
2. <experiment 2>
3. <experiment 3>

## Step 1: Experience
<full answer>

**Marginal gain:** <user's answer>

## Step 2: Reflection
### Sequence of events
...
### Feelings
...
### Difficult / Went well
...
### Response to difficulties
...
### Triggers
...
### Why I acted that way
...

## Step 3: Abstraction
### Habits, beliefs, tendencies
...
### Similar patterns in other parts of life
...

## Step 4: Experiments
1. ...
2. ...
3. ...

### Parking lot
- ...

## Powiązane
- [[previous cycle if any]]
```

Path: `<vault>/Osiąganie swoich celów/Kolbs/YYYY-MM-DD-<slug>.md`

Slug = kebab-case short summary of Experience, max 5 words.

**Before writing:** show the full note in chat. Wait for explicit OK.

### 6. Update index

After saving the cycle note, update `<vault>/Osiąganie swoich celów/Kolbs/_index.md`:

```markdown
# Kolb's Index

## Active experiments
- [[2026-05-20-debugowanie-pod-presją]] — Pre-debug hypothesis (open, deadline 2026-05-27)
- ...

## Closed experiments
- [[2026-05-15-...]] — ... (tested → worked / abandoned)

## All cycles
- 2026-05-20: [[2026-05-20-debugowanie-pod-presją]]
- ...
```

When the new cycle references a `previous`, also flip the relevant experiment in the previous cycle's frontmatter from `open` → `tested` or `abandoned` (ask user which). Reflect that in `_index.md` too.

### 7. Final delivery (in chat, after save)

After the note and index are saved, end the session with an explicit punch list in chat. This is the moment the user walks away from. Format:

```
✅ Zapisane: [[YYYY-MM-DD-slug]]

🎯 Twoje ruchy na najbliższy tydzień / dwa:

1. <eksperyment 1> — pierwszy konkretny krok: <co robisz jutro rano>
2. <eksperyment 2> — pierwszy krok: ...
3. <eksperyment 3> — pierwszy krok: ...

📅 Sugerowany termin następnego Kolb's: <data, np. za 1-2 tygodnie>
   (wtedy zreflektujemy które eksperymenty zadziałały)
```

Bez tej sekcji cykl ginie w plikach. To jest wynik dla użytkownika.

## Detailed guidelines

- Per-step criteria, depth signals, and Sung's full rationale: see [REFERENCE.md](REFERENCE.md)
- Reframing examples (good vs. bad Experiences, Abstractions, Experiments): see [EXAMPLES.md](EXAMPLES.md)

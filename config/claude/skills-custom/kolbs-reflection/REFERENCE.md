# Kolb's Reflection — Reference

Full Justin Sung-style guidelines for each step. Read the relevant section when you need to validate, reframe, or push the user deeper.

---

## Step 1: Experience — the 4 filters

Experience is the foundation; if it's wrong, the whole cycle is wasted.

### Process-focused (not outcome)

- **Wrong**: "I failed the test" / "My PR got rejected" / "My code is slow"
- **Right**: "How I prepared for the test the night before" / "How I reacted when reading the review comments" / "How I went about optimizing the function"

Outcomes are symptoms. Processes are the levers. If the user reflects on the outcome, the experiments will treat symptoms, not causes.

**Reframe prompt**: "That's the outcome — what part of the *process* leading to that outcome is the one you want to improve? Or what was your *reaction* to that outcome?"

### Specific (single event)

- **Wrong**: "All my code reviews last sprint" / "How I learn in general" / "My productivity this week"
- **Right**: "The code review of PR #142 yesterday" / "Studying React hooks Tuesday evening"

Multiple events have multiple confounders. The patterns won't be clean.

**Reframe prompt**: "Across all of those, which single event was the most striking or surprising? Let's reflect on that one specifically — others can be separate cycles."

### Recent (last ~2 weeks)

Older experiences = lost detail = inflated narrative.

**Reframe prompt**: "What's the most recent comparable experience? Memory fades fast — we want one where you still remember how you felt minute-by-minute."

### Concise (1 sentence)

Brevity now; we elaborate in Reflection. Sprawl here = unfocused cycle.

**Reframe prompt**: "Try compressing that to one sentence — what's the actual core event?"

---

## Step 1.5: Marginal gain

After Experience passes, ask: **"What would a marginal gain look like here?"**

Remind the user that marginal gains look different at different stages of the conscious competence model:
- Unconscious incompetence → just recognizing the problem exists
- Conscious incompetence → noticing it in the moment without yet fixing it
- Conscious competence → applying a deliberate fix that requires attention
- Unconscious competence → it happens automatically

Don't validate this answer hard — it primes direction for the rest of the cycle, that's all.

---

## Step 2: Reflection — depth signals

For each question, watch for **shallow markers** and grill until they're gone (max 2-3 follow-ups per question).

### Shallow markers

- Generic adjectives: "frustrated", "tired", "annoyed" with no specificity
- Universal claims: "always", "never", "every time"
- Outcome-leaking: "I felt bad because the result was bad" (circular)
- Theorizing during reflection: "I'm probably the kind of person who…" (this belongs in Step 3)
- "I don't know" without trying

### Grilling prompts per question

**Sequence of events:**
- "What happened immediately before X?"
- "How long did Y take? Was there a pause?"

**Feelings:**
- "Was that frustration in your body? Where?" (somatic markers help)
- "Did the feeling shift at any point? When?"
- "On a 1-10 intensity scale, what was it at the peak?"

**What felt difficult / went well:**
- "Difficult in what sense — mentally, emotionally, technically?"
- "Was anything *unexpectedly* easy or hard?"

**Response to difficulties:**
- "Be honest: did you avoid, retreat, distract yourself? Open a new tab? Quit and come back later?"
- "What was the first thing you reached for — not the thing you tried second?"

**Triggers (external):**
- "What did you see/hear/touch right before that feeling started?"
- "Is there a specific moment in the timeline where things shifted?"

**Why you acted that way (internal):**
- "What emotion or belief was driving that choice?"
- "If you slowed it down — what thought went through your head right before you acted?"

### When user is stuck

1. Reframe the question from a different angle (concrete → abstract or vice versa).
2. Offer a pattern-priming example **from a different life domain** (never the user's current situation):
   - "Some people, when they feel overwhelmed by docs they don't understand, close the tab and switch to a familiar task. Does anything like that resonate?"
   - Use mundane domains: cooking, exercise, social situations, sleep.
3. If still stuck after 2 reframes: explicitly note this as a self-awareness gap. Per Sung: "Your marginal gains will involve improving your self-awareness for next time, while practising these reflective questions to the best of your ability now." Move on without forcing a fake answer.

### Time-budget check-in

After Reflection, ask: "Jesteśmy w połowie. Czujesz, że refleksja jest wystarczająco głęboka, by zbudować na niej Abstraction? Możemy też zapisać draft i wrócić."

If the user says draft → save partial note with `status: draft` in frontmatter, and an explicit `TODO` marker showing where to resume.

---

## Step 3: Abstraction — root-cause vs. theorizing

Abstraction = *analysis of reflection data*, not free-form psychology.

### The supported-by-reflection rule

Every pattern named must point to evidence in the Reflection. If the user names a pattern that's not supported:

- **Push back**: "What in your reflection points to that?"
- **If nothing**: "Then we're theorizing. Note it as a hypothesis to watch in your next experience, not as established."

### Three failure modes (per Sung)

1. **Reflection too brief/superficial** → go back to Step 2, deepen specific questions, then return.
2. **Self-awareness not high enough** → if user can't add detail to Reflection even when prompted, accept it. Note as a self-awareness gap, target it in Experiments.
3. **Not used to analysing reflections** → do best, expect improvement over cycles.

### Pattern-quality check

Good patterns are:
- **Causal** (explain "why I acted"), not just descriptive ("I was tired")
- **Recurring** (also show up in other parts of life — Step 3 second question)
- **Specific to a trigger or condition** ("when I feel overwhelmed", "when stakes are high"), not universal ("I'm lazy")

If a pattern is descriptive only, ask: "And what makes that happen? What condition or feeling precedes it?"

---

## Step 4: Experiment — actionable specificity

### Hard rules from Sung

- **<3 ideal, >4 strongly discouraged.** Force the user to rank.
- **Concise, specific, actionable.** "Be more focused" → "Phone in another room before each study session."
- **Imagine waking up tomorrow and seeing the list.** Can you act immediately, or do you need to interpret?

### Specificity test

For each experiment, ask:
- "When exactly will you do this — what's the trigger?"
- "What's the smallest version of this you can do tomorrow morning?"
- "How will you know it worked?" (don't over-engineer — a rough sense is fine)

### Parking lot

Experiments that didn't make the top 3 go to `parking_lot:` in frontmatter. They're not lost — they're queued. Next cycle, the index will surface them if relevant.

### Optional deadline

Suggest a soft deadline (1-2 weeks) per experiment. This becomes the natural cadence for the next Kolb's cycle. Don't be rigid — sometimes the right answer is "test this for a month".

---

## Compounding loop (cross-cycle)

Each new cycle either:

1. **Tests a previous experiment** → frame the Experience around how that test went. At the end, flip the experiment's status to `tested` (worked/didn't) or `abandoned` (didn't even try, and why) in the *previous cycle's* frontmatter.
2. **Opens a new thread** → standalone, no `previous` link.

The `_index.md` dashboard surfaces open experiments at session start. This is what makes gains *compound* — without surfacing, the user re-invents the wheel each cycle.

---

## Anti-patterns to push back on

- **Outcome reflection** ("the result was X, so I felt Y") — outcome ≠ process.
- **Multi-event sprawl** ("this whole sprint…") — kill specificity.
- **Theorizing without evidence** in Step 3 — reintroduces cognitive bias.
- **Vague experiments** ("be more disciplined", "focus better") — useless on Tuesday morning.
- **>3 experiments** with "they're all important" — they're not. Force-rank.
- **Skipping difficulty questions** because user doesn't want to admit avoidance — gently push: "Be honest with yourself, not with me — what *actually* happened?"

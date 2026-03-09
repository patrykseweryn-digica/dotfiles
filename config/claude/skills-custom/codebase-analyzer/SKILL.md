---
name: codebase-analyzer
description: |
  Analyze any codebase from 4 dimensions in parallel using Explore subagents: architecture, code quality,
  TODO/technical debt, and security surface. Produces a unified report with executive summary and
  prioritized recommendations. Use when user asks to: analyze a codebase, audit code quality,
  get a codebase overview, review code health, assess technical debt, scan for security issues,
  or understand a new project's structure. Triggers on "analyze codebase", "code audit",
  "codebase overview", "code review", "project analysis", "code health check".
---

# Codebase Analyzer

Analyze any codebase from 4 dimensions simultaneously using parallel Explore subagents, then aggregate findings into a unified report.

## How It Works

This skill launches **4 parallel Explore subagents** via the Task tool — each specialized in a different analysis dimension:

1. **Architecture Scout** — maps structure, languages, frameworks, entry points, dependencies, build tools
2. **Code Quality Auditor** — finds long functions, deep nesting, error handling issues, test coverage gaps
3. **TODO/FIXME Hunter** — greps all TODO/FIXME/HACK/XXX/WORKAROUND markers, categorizes by severity
4. **Security Surface Scanner** — checks for hardcoded secrets, injection risks, auth gaps, CORS issues

All 4 run concurrently in a single message (no sequential waiting), making this much faster than running them one at a time. Each subagent uses `subagent_type="Explore"` which is read-only and safe.

## Workflow

### Step 1: Determine Scope

Ask the user which codebase to analyze if not obvious. Resolve the absolute path.

- If user says "this codebase" or "current project", use the current working directory
- If user provides a path, resolve it to absolute
- Confirm the path exists before proceeding

Store the resolved path as `ROOT` for use in the prompts.

### Step 2: Launch 4 Parallel Subagents

**Read the file `references/subagent-prompts.md`** to get the 4 prompt templates. Replace `{ROOT}` with the actual codebase path.

Then launch all 4 Task calls **in a single message** — this is critical for parallelism. Use `subagent_type="Explore"` for all.

Here is an annotated example of the 4 parallel Task calls:

```
# All 4 of these must go in ONE message to run in parallel.
# Do NOT send them one at a time.

Task call 1:
  description: "Analyze codebase architecture"
  subagent_type: "Explore"
  prompt: [Architecture Scout prompt with {ROOT} replaced]

Task call 2:
  description: "Audit code quality"
  subagent_type: "Explore"
  prompt: [Code Quality Auditor prompt with {ROOT} replaced]

Task call 3:
  description: "Hunt TODOs and FIXMEs"
  subagent_type: "Explore"
  prompt: [TODO/FIXME Hunter prompt with {ROOT} replaced]

Task call 4:
  description: "Scan security surface"
  subagent_type: "Explore"
  prompt: [Security Surface Scanner prompt with {ROOT} replaced]
```

Each subagent will return structured findings in the format specified by its prompt template.

### Step 3: Aggregate Into Report

Once all 4 subagents return, compile their findings into the unified report format below.

## Report Template

Print the report directly in the conversation. Use this structure:

```markdown
# Codebase Analysis Report: [project name]

**Analyzed**: [date]
**Path**: [ROOT]
**Analyzed by**: 4 parallel Explore subagents

---

## Executive Summary

[2-4 sentences synthesizing the most important findings across all 4 dimensions.
Highlight the overall health, biggest risks, and most impactful improvements.]

**Health Score**: [Healthy / Moderate / Needs Attention / Critical] — [one-line justification]

---

## 1. Architecture

[Paste Architecture Scout findings, lightly edited for consistency]

---

## 2. Code Quality

[Paste Code Quality Auditor findings, lightly edited for consistency]

---

## 3. Technical Debt (TODOs/FIXMEs)

[Paste TODO/FIXME Hunter findings, lightly edited for consistency]

---

## 4. Security Surface

[Paste Security Surface Scanner findings, lightly edited for consistency]

---

## Prioritized Recommendations

Cross-reference findings from all 4 dimensions and produce a unified priority list:

| # | Recommendation | Category | Severity | Effort |
|---|---------------|----------|----------|--------|
| 1 | ... | Security/Quality/Debt/Arch | Critical/High/Med/Low | Low/Med/High |
| 2 | ... | ... | ... | ... |
| ... | ... | ... | ... | ... |

Focus on recommendations where multiple dimensions reinforce the same finding
(e.g., a FIXME about missing input validation confirmed by the security scanner).
```

## Aggregation Instructions

When merging subagent results into the final report:

1. **Cross-reference**: If the TODO hunter found a `FIXME: SQL injection here` and the security scanner independently flagged the same file for injection risk, merge these into a single high-priority recommendation and note the corroboration.

2. **Prioritize by convergence**: Findings confirmed by multiple subagents get bumped up in priority. A code quality issue that also has security implications ranks higher than a standalone cosmetic issue.

3. **Executive summary**: Don't just list findings — synthesize. What's the overall story? Is this a well-maintained codebase with minor debt? A security-risky codebase with good architecture? A quality codebase hampered by technical debt?

4. **Health score criteria**:
   - **Healthy**: No critical/high security issues, good test coverage, manageable TODOs, clean architecture
   - **Moderate**: Some high-priority issues but no critical ones, reasonable coverage, some debt
   - **Needs Attention**: Critical security issues OR very low test coverage OR excessive debt OR unclear architecture
   - **Critical**: Multiple critical security issues AND poor quality AND significant debt

5. **Be specific**: Every recommendation should reference specific files and line numbers when available. Vague advice like "improve error handling" is less useful than "add error handling to `src/api/users.ts:45` where database errors are silently swallowed."

6. **Credit good practices**: The report should also note what the codebase does well. This gives context and avoids being purely negative.

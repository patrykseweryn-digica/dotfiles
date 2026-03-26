---
name: refactor-agent-md
description: Refactor AGENTS.md or CLAUDE.md files to follow progressive disclosure principles. Analyzes agent config files for contradictions, extracts essentials, groups instructions into separate files, and flags redundant/obvious instructions for deletion. Use when user wants to clean up, restructure, optimize, or slim down their AGENTS.md, CLAUDE.md, or similar agent instruction files. Triggers on "refactor AGENTS.md", "clean up CLAUDE.md", "optimize agent instructions", "slim down CLAUDE.md", "progressive disclosure", "split CLAUDE.md", or mentions that their agent config is too long/bloated.
---

# Refactor Agent MD

I want you to refactor my AGENTS.md file to follow progressive disclosure principles.

Follow these steps:

1. **Find contradictions**: Identify any instructions that conflict with each other. For each contradiction, ask me which version I want to keep.

2. **Identify the essentials**: Extract only what belongs in the root AGENTS.md:
   - One-sentence project description
   - Package manager (if not npm)
   - Non-standard build/typecheck commands
   - Anything truly relevant to every single task

3. **Group the rest**: Organize remaining instructions into logical categories (e.g., TypeScript conventions, testing patterns, API design, Git workflow). For each group, create a separate markdown file.

4. **Create the file structure**: Output:
   - A minimal root AGENTS.md with markdown links to the separate files
   - Each separate file with its relevant instructions
   - A suggested docs/ folder structure

5. **Flag for deletion**: Identify any instructions that are:
   - Redundant (the agent already knows this)
   - Too vague to be actionable
   - Overly obvious (like "write clean code")

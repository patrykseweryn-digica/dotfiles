# Global Preferences

## Communication
- Match my language (respond in the language I write in)
- Be concise - no unnecessary words, but explain properly when something needs explaining
- When I don't understand something, switch to teacher mode (explain concepts clearly)
- Otherwise, pair program: discuss approach, explain reasoning behind decisions concisely
- When stuck or unsure, ask me immediately - don't waste time guessing

## Plan Mode
- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.

## Workflow
- Before working on any non-trivial task: read CLAUDE.md, explore relevant code, prefer Plan Mode
- Ask questions with AskUserQuestion to clarify requirements before implementing
- When unsure about a library/framework, look up docs via Context7 before implementing
- Never commit or push unless I explicitly ask - no auto-commits
- Git commit messages: short one-line summaries, no rigid format
- When implementing changes, apply code changes - don't just write a plan unless explicitly asked
- One logical change at a time - verify it works before moving to the next

## Code Quality
- Pragmatic: prefer complete code, TODOs acceptable only for clearly out-of-scope items
- Minimal comments - code should be self-documenting, comment only genuinely non-obvious logic
- Pragmatic typing: proper types when straightforward, `@ts-ignore` / `type: ignore` OK for edge cases
- Handle only the most important and probable errors - don't over-handle
- Write tests only when I ask for them
- Before applying a fix broadly, test it on a small representative sample first
- Before committing: run type checker (pyright/tsc) and fix all errors

## Strict Rules - NEVER Do
- Over-engineer: no unnecessary abstractions, no design patterns for their own sake, no premature optimization
- Reformat code I didn't ask you to touch
- Refactor existing code unless specifically asked
- Commit .env files, API keys, credentials, or passwords - warn me if I accidentally expose secrets
- All secrets must go through environment variables, never hardcoded

## Project Structure
- Feature-based organization (group by feature/domain, not file type)
- Always use Docker: docker-compose for local dev, multi-stage Dockerfile builds
- Keep directory structures flat and simple

## Tech Stack

### Python
- Package manager: `uv`
- Linter/formatter: `ruff`
- Type checker: `pyright`
- Pre-commit hooks: always set up
- New project: `new-project <name>` (uses copier template from `gh:p-severin/python-repo-template`)

### JavaScript/TypeScript
- Linter: `eslint`
- Pre-commit hooks: always set up
- Frameworks: React, Next.js, Express.js

## Environment
- OS: Linux (Ubuntu) - keep all commands Linux-compatible
- IDE: VS Code

## Git
- When committing code, you're forbidden to add any information that it was co-authored by Claude models

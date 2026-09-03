---
name: git-guardrails-claude-code
description: "Set up Claude Code or Codex hooks to block dangerous git commands (push, reset --hard, clean, branch -D, checkout ., restore ., etc.) before they execute. Use when the user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code or Codex."
---

# Setup Git Guardrails

Set up a `PreToolUse` hook that intercepts and blocks dangerous git commands before Claude Code or Codex executes them.

## What Gets Blocked

- `git push` (all variants including `--force`)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

When blocked, the agent receives a stderr message and the hook exits with code `2`.

For Codex, treat this as a guardrail, not a complete enforcement boundary. Codex `PreToolUse` can intercept Bash commands, but not every possible shell/tool path.

## Steps

### 1. Choose target and scope

Determine whether the user wants **Claude Code**, **Codex**, or both. Ask only if ambiguous.

Ask scope:

- **Claude project**: `.claude/settings.json`
- **Claude global**: `~/.claude/settings.json`
- **Codex project**: `.codex/hooks.json` or `.codex/config.toml`
- **Codex global**: `~/.codex/hooks.json` or `~/.codex/config.toml`

For Codex, prefer `hooks.json` when no inline `[hooks]` already exists. If inline hooks already exist in `config.toml`, merge there to avoid mixed-source warnings.

### 2. Copy the hook script

The bundled script is at [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh). Copy it based on target:

- **Claude project**: `.claude/hooks/block-dangerous-git.sh`
- **Claude global**: `~/.claude/hooks/block-dangerous-git.sh`
- **Codex project**: `.codex/hooks/block-dangerous-git.sh`
- **Codex global**: `~/.codex/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

### 3. Configure Claude Code

For Claude Code, add to the appropriate settings file.

Project `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

Global `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If the settings file already exists, merge the hook into `hooks.PreToolUse`; do not overwrite other settings.

### 4. Configure Codex

For Codex, add a `PreToolUse` hook with matcher `^Bash$`.

Project `.codex/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "\"$(git rev-parse --show-toplevel)/.codex/hooks/block-dangerous-git.sh\"",
            "statusMessage": "Checking git command"
          }
        ]
      }
    ]
  }
}
```

Global `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "^Bash$",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.codex/hooks/block-dangerous-git.sh",
            "statusMessage": "Checking git command"
          }
        ]
      }
    ]
  }
}
```

If `hooks.json` or `config.toml` already contains hooks, merge into the existing `hooks.PreToolUse` array; do not overwrite other hooks.

After configuring Codex, tell the user to run `/hooks` in the Codex CLI to review and trust the hook. New or changed non-managed command hooks are skipped until trusted.

### 5. Ask about customization

Ask if user wants to add or remove any patterns from the blocked list. Edit the copied script accordingly.

### 6. Verify

Run a quick test:

```bash
echo '{"tool_input":{"command":"git push origin main"}}' | <path-to-script>
```

Should exit with code 2 and print a BLOCKED message to stderr.

Also verify an allowed command:

```bash
echo '{"tool_input":{"command":"git status --short"}}' | <path-to-script>
```

Should exit with code 0 and print nothing.

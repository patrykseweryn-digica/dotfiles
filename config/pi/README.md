# Pi configuration

`settings.json` owns preferences and the tested extension versions/commits.
`models.json` owns only the three Codex context-window overrides; sync merges
these into local overrides without deleting other models, fields or auth.
Themes and local extensions are linked individually. Herdr's extension,
credentials, sessions, caches and Fast Mode state remain unmanaged.

```sh
./sync-agents.sh pi-install
./sync-agents.sh pi-check
# In an already running Pi session:
/reload
```

`pi-check` compares JSON values, not formatting or key order. It also checks
installed package versions/commits, model overrides and theme/extension files.
Changing a linked theme or extension changes its source in dotfiles.

## Interface

Rose Pine Moon's palette and token mapping live in
`themes/rose-pine-moon.json`. `terminal.trueColor=true` keeps that palette
accurate inside the existing RGB-capable tmux setup: autodetection there
otherwise quantizes the surface to an unintended blue. This changes Pi only,
not the terminal's settings or built-in dark theme.

Images remain available to the model but are not rendered in the terminal.
Both queue modes deliver **all queued messages** together; they do not force
parallel task execution. Quiet startup and collapsed changelog apply to Pi;
extensions may still display their own notices.

The title extension shows a braille spinner, `π`, and up to 40 graphemes from
the session name (directory basename otherwise). Control characters are
removed. `idle`, `ended`, `error` and `aborted` are distinct; `ended` does not
claim verified task success. Only `agent_settled` ends an agent run, not
`agent_end`. Tool errors alone do not mark the session failed.

A single TUI-only 120 ms timer reasserts the title even while idle because
Pi writes its default title after asynchronous startup, reload and rename.
Only active work animates. Shutdown/session replacement clears the timer.
RPC, JSON and print do not start it or emit title updates.

## Server compaction

The package remains at the exact requested upstream commit, unchanged.
Its declared Pi range is `>=0.80.9 <0.81.0`, while deployment targets latest.
The narrow declared range is not proof of runtime incompatibility; repeat
the live check after Pi upgrades rather than downgrading Pi.

Compaction runs two requests: native OpenAI compaction and a portable text
summary. Context is sent to the provider; opaque artifacts are stored in
local session JSONL. Direct `openai/*` additionally enables `store:true` and
server-side continuation. Codex retains Pi's built-in transport. Remote
compaction usage is stored in details and is not fully included in ordinary
session totals. Expect extra usage; never commit artifacts or credentials.

Emergency bypass: `PI_OPENAI_SERVER_COMPACTION_ENABLED=0 pi`, or run with
`--no-extensions` to bypass extensions entirely. Neither changes the pins.

## MCP audit: retain both adapters

Audit on 2026-09-15, with pi-mcp-adapter 2.34.0 and pi-mcporter 1.0.2:

- **pi-mcporter:** existing seven-server inventory, discovery, schemas and
  execution through MCPorter's configuration and OAuth store.
- **pi-mcp-adapter:** native `mcpScript` batching plus MCP URL installation,
  OAuth UI and runtime registration. MCPorter does not provide this Pi
  scripting/UI surface. In 30 recent session files, excluding this work's
  session, tool-name-only inspection found four `mcpScript` calls, two `mcp`
  calls and eight `mcporter` calls. Removing it would remove a used workflow.
- No source imports, event-bus registration dependencies or `pi.mcp` package
  manifests were found in the other installed extensions. This is a workflow
  dependency, not an invented hard dependency between packages.
- The adapter reads shared global MCP files and Pi overrides. After restore,
  `~/.agents/mcp.json` supplies five servers; the earlier zero-server snapshot
  was not evidence that the adapter's scripting functions were unused.
- MCPorter currently imports five servers from `~/.claude/settings.json`,
  Telegram from `~/.claude.json`, and OpenAI docs from `~/.codex/config.toml`.
  Those files and both credential stores were not migrated or removed.

Known existing failures, not lost configuration: Garmin's dependency resolves
MCP Python 2.x but imports `mcp.server.fastmcp`; Telegram lacks
`TELEGRAM_API_ID` in this runtime; Todoist requires authentication. All seven
names remain discoverable. Do not interpret unavailable schemas as deletion.

## Verification: 2026-09-15

- Pi **0.85.1** matched npm **latest 0.85.1**. No other CLI was upgraded.
- Actual package install into an isolated HOME, second install with no package
  changes, semantic drift check, then the same checks against the live HOME.
- All original eleven extensions loaded; final live runtime loads fourteen
  entries including unchanged Herdr, terminal title and server compaction.
- Actual Codex **gpt-5.6-sol**, requested compaction commit: first response,
  native `responses_compaction_v2` artifact, replay on the next request,
  codeword recall with the word removed from the text summary, process/session
  recreation and native replay again. Switching to **zai/glm-5.3-flash**
  completed another turn without native replay. All passed, no source patch.
- Effective Luna/Sol/Terra limits: **272000** each.
- TUI in tmux: inspected ordinary message, highlighted code, diff and error;
  selected dark then Moon; modified an isolated theme copy and verified hot
  reload by its actual accent escape sequence. No missing tokens.
- TUI title: observed multiple braille frames, `ended` after a live response,
  `aborted` after Escape, rename and reload. The unchanged Herdr integration
  concurrently reported idle/working/idle to an isolated local socket.
  Actual Herdr desktop-panel rendering was not available in this tmux session.
- Fresh SDK session and reload: all seven MCP server names, OpenAI docs schema
  lookup and read-only `list_api_endpoints` execution passed. No external
  mutations or reauthentication were performed.

## Repository checks

Node 24+ is required. Development dependencies are only for checks; Pi loads
the extension with its own runtime. The development Pi pin records the API
used for type/schema validation, not the CLI installation policy.

```sh
npm --prefix config/pi ci --ignore-scripts
npm --prefix config/pi run check
npm --prefix config/pi test
just check
```

Pre-commit runs types, ESLint, Prettier and the deterministic Pi regression
checks. They do not call models or registries. Live checks are separate and
require working provider credentials, quota and MCP connectivity.

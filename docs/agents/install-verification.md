# Installation fixes #32-#35

Verified on 2026-09-15. Base commit: `dd5b7d2`.

## Behavior

- Codex exports enabled, installed plugins with a Git marketplace source.
  Local marketplace paths are runtime state, not portable install sources.
  The rule uses source metadata, not an OpenAI name blacklist. Remote
  connectors retain their separate manifest and interactive OAuth workflow.
- The manifest now requires the three Git plugins: last30days, logfire,
  and ponytail. The eleven bundled/runtime requirements were removed.
  Checks require declared plugins and sources; additional Codex plugins
  and marketplaces are preserved. Export can include those user additions.
- Full installation prepares Node and developer tools before agent sync.
  Agent sync adds marketplaces, installs/enables missing required Codex
  plugins, then checks state. Marketplace source conflicts fail explicitly.
- Treehouse downloads official release archives via the public latest-release
  redirect. Extraction and execution checks precede replacement in the user's
  bin directory. Failed downloads preserve the installed binary.
- The poteto-mode lock entry declares upstream `installName: Poteto Mode`.
  Skills CLI installs into Codex's shared skill directory; existing runtime
  linking distributes it to Claude, OpenCode and Pi. Upstream lock rewrites
  are reconciled with repository intent. Missing required skills fail install
  with CLI output visible. Resolving the source directory prevents link cycles.

## Reproduced causes

- Treehouse's upstream shell installer called
  `https://api.github.com/repos/kunchenguid/treehouse/releases/latest`.
  HTTP 403 contained `API rate limit exceeded`; response headers reported
  limit 60 and remaining 0. No credentials are needed for the new route.
- Skills 1.5.23 rejected `--skill poteto-mode` with
  `No matching skills found`. Upstream frontmatter names it `Poteto Mode`.
  A fresh home also exposed broad runtime autodetection and a lock rewrite
  under the upstream display name. Explicit agent selection and lock
  reconciliation address those cases.

## Real executions

Linux x86_64:

- `just install`: every installation step succeeded.
- `sync-agents.sh codex-plugins-check`: passed against live state.
- Treehouse v2.3.0 installed and executed in a fresh temporary bin directory.
- Codex installed ponytail from Git in an empty temporary Codex home.
  Re-adding it after setting `enabled = false` restored `enabled = true`.
- Poteto Mode installed through `push-skills` in an empty temporary home.
  The command passed on both the first and second run, checking all four
  managed skill directories.

## Review

Standards and Spec reviews each found two defects. Backup error handling,
test isolation, aliased-home linking and optional-URL parsing were fixed
and covered by regression tests.

## Regression checks and limits

Pre-commit includes focused tests for portable pull/check, skill installation,
Treehouse download/retry, and the full `just install` plugin flow. The latter
uses real repository control flow with external installers and Codex transport
simulated. Cases include missing CLI, empty/partial/complete plugin state,
failed download/retry, additional plugins, and home paths containing spaces.
Skill regressions also cover aliased homes, omitted optional source URLs,
backup failures and repeat runs. MCP sentinel checks protect live overrides.
Linux/macOS x86_64 and ARM64 branches are simulated, not native executions.
Treehouse's published assets cover these four combinations; unsupported OS
or architecture values fail explicitly. Linux user-local paths require no sudo.

Bundled Codex runtime metadata is unavailable on this host. The host's real
Git marketplace metadata and absent-bundle state were inspected; local bundled
presence is covered by fixtures. Native macOS and ARM64 execution remain
unverified. Remote connectors on a new account may still require interactive
installation and OAuth; no account cache is copied.

The broad live `skills-check` also reported existing unmanaged skills, stale
`craft-readme` links and `pluginName` metadata differences. These are separate
from poteto-mode; the dedicated fresh-home skill check passes. Extra live skills
were not deleted to make this unrelated inventory check pass.

Sources: [Treehouse installer](https://kunchenguid.github.io/treehouse/install.sh),
[release assets](https://github.com/kunchenguid/treehouse/releases/tag/v2.3.0),
[Poteto Mode](https://github.com/cursor/plugins/blob/main/pstack/skills/poteto-mode/SKILL.md),
[Skills CLI](https://github.com/vercel-labs/skills).

# Vale template

Vale checks Markdown spelling. The Firstmate vocabulary accepts agent terms
without hiding unknown words. Inline code and fenced code remain code.

## Use in a repository

1. Copy `.vale.ini` and `styles/` beside the target repository's README.
2. Merge `pre-commit.yaml` into the repository's pre-commit configuration.
3. Install Vale 3.27.0 through mise with `aqua:errata-ai/vale@3.27.0`.
4. Run `pre-commit run vale --all-files`.

The dotfiles inventory owns the installation pin.
The template needs no remote styles or `vale sync`.
Add intentional project terms to
`styles/config/vocabularies/Firstmate/accept.txt`.
Keep spelling mistakes out of the vocabulary.

## Agents and CI

Pi with pi-lens detects a repository's `.vale.ini` automatically.
If `.vale.ini` exists, Codex, Claude, and Firstmate should run
`vale <changed-markdown-paths>` before finishing Markdown changes.
The same rule applies to Pi when automatic diagnostics are unavailable.

CI should install the same Vale version and run the same pre-commit hook.
Both paths use the repository's `.vale.ini` and vocabulary.
Do not maintain a separate CI spelling configuration.

## Verify the template

From the dotfiles root:

```sh
vale --config=config/vale/.vale.ini config/vale/README.md
```

Dotfiles does not enable a repository-wide Vale gate.
Existing prose needs a separate vocabulary review before enabling the hook.

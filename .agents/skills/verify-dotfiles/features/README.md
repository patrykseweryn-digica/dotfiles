# Dotfiles verification map

Use the checkout root and the evidence directory from SKILL.md.
Run the affected recipes after each change; `just test` runs them all.

- [Setup and synchronization](setup.md): isolated installation and config sync.
- [Tool inventory and updates](tools.md): latest tools without repo rewrites.
- [Machine check](machine.md): live drift, safe diagnostics and read-only checks.
- [Install groups](groups.md): per-machine core, agents and desktop selection.

Record the feature, command, platform, exit code and observable result.
A simulated installer is not proof of a successful external download.
An unexecuted Linux CI job is not Linux verification.

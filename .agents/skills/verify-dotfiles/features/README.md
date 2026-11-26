# Dotfiles verification map

Use the checkout root and the evidence directory from SKILL.md.
Run the affected recipes after each change; `just test` runs them all.

- [Setup and synchronization](setup.md): isolated installation and config sync.
- [Tool inventory and updates](tools.md): latest tools without repo rewrites.
- [Machine check](machine.md): live drift, safe diagnostics and read-only checks.
- [Install groups](groups.md): per-machine group selection and the install
  tree declaration.
- [Commit hooks](hooks.md): staged-file selection and full-suite coverage.
- Command menu: run `just` and `make` at 80 columns on a terminal, with
  `NO_COLOR=1`, piped, and `PATH=/usr/bin:/bin make help` without `just`.
  Then run `bash scripts/smoke-menu.sh`: it checks the group status, the
  colors, the line width, and that both runners list the same commands.
- Architecture map: run `just architecture`, then
  `prek run architecture-map --all-files` to check both generated files.

Record the feature, command, platform, exit code and observable result.
A simulated installer is not proof of a successful external download.
An unexecuted Linux CI job is not Linux verification.

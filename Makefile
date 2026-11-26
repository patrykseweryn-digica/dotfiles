# GNU Make alternative to the public just recipes. Keep the scripts shared.
# Make must work without just. scripts/smoke-menu.sh fails when this help
# drifts from `just --list --unsorted`.
.DEFAULT_GOAL := help
.NOTPARALLEL:
.PHONY: help install machine sync groups enable disable export export-skills \
	test architecture

export DOTFILES_RUNNER := make
export group
export SYNC_AGENTS ?= ./sync-agents.sh

help:
	@printf '%s\n' \
		'Available targets:' \
		'    [start]' \
		'    install            # Install tools, links, agent config, SSH and hooks.' \
		'    machine            # Check this machine against the repo; read-only.' \
		'' \
		'    [daily]' \
		'    sync               # Pull repository changes, then update this machine.' \
		'' \
		'    [install groups]' \
		'    groups             # Show the install groups of this machine.' \
		'    enable group=NAME  # Select an install group, then install its elements.' \
		'    disable group=NAME # Stop updating an install group; keep its elements.' \
		'' \
		'    [export]' \
		'    export             # Save local additions; `export-skills` picks skills.' \
		'' \
		'    [dev]' \
		'    test               # Run all repository checks; required before commits.' \
		'    architecture       # Regenerate the architecture SVG and JSON.'

install:
	@./install.sh

machine:
	@./scripts/doctor.sh

sync:
	@./scripts/sync-local.sh

groups:
	@bash scripts/groups.sh show

enable:
	@bash scripts/groups.sh enable "$$group"
	@./install.sh

disable:
	@bash scripts/groups.sh disable "$$group"

export:
	@"$$SYNC_AGENTS" export

export-skills:
	@"$$SYNC_AGENTS" export skills

# Checks clear the variables exported above; see scripts/test.sh.
test:
	@bash scripts/test.sh

architecture:
	@python3 scripts/build-architecture.py

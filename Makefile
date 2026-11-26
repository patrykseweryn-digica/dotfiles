# GNU Make alternative to the public just recipes. Keep the scripts shared.
.DEFAULT_GOAL := help
.NOTPARALLEL:
.PHONY: help install sync machine groups enable disable export export-skills

export DOTFILES_RUNNER := make
export group
export SYNC_AGENTS ?= ./sync-agents.sh

help:
	@printf '%s\n' 'make install' 'make sync' 'make machine' 'make groups' \
		'make enable group=NAME' 'make disable group=NAME' \
		'make export' 'make export-skills'

install:
	@./install.sh

sync:
	@./scripts/sync-local.sh

machine:
	@./scripts/doctor.sh

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

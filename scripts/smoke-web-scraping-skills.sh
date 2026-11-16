#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${DOTFILES_DIR}/.agents/skill-lock.json"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

locked=(
    anki-export
    crawlee-build
    generate-flashcards
    hook-setup
    kolbs-reflection
    mlflow-analyzer
    obsidian-notes
    plain-talk
    project-statement
    scrapy-build
    scrapy-deploy
    show-the-change
    web-scraping-ops
    web-scraping-pipeline-design
    web-scraping-references
    web-scraping-scout
    web-scraping-simple
    write-digica-readme
)

removed=(
    web-scraping-audit
    web-scraping-debug
)

kept=(
    ask-matt
    last30days
    design-control-loop
)

for name in "${locked[@]}"; do
    [ ! -e "${DOTFILES_DIR}/.agents/skills-custom/${name}" ] ||
        fail "personal skill still copied in skills-custom: ${name}"
    jq -e --arg name "$name" '
        .skills[$name] as $skill |
        $skill.source == "p-severin/skills" and
        $skill.sourceType == "github" and
        $skill.sourceUrl == "https://github.com/p-severin/skills.git" and
        $skill.skillPath == ($name + "/SKILL.md") and
        ($skill.ref | not)
    ' "$LOCK" >/dev/null ||
        fail "personal skill lock entry is wrong: ${name}"
done

for name in "${removed[@]}"; do
    jq -e --arg name "$name" '.skills[$name] | not' "$LOCK" >/dev/null ||
        fail "removed skill still locked: ${name}"
    [ ! -e "${DOTFILES_DIR}/.agents/skills-custom/${name}" ] ||
        fail "removed skill still copied: ${name}"
done

for name in "${kept[@]}"; do
    [ -f "${DOTFILES_DIR}/.agents/skills-custom/${name}/SKILL.md" ] ||
        fail "vendored skill missing: ${name}"
done

[ -f "${DOTFILES_DIR}/.agents/skills/verify-dotfiles/SKILL.md" ] ||
    fail "verify-dotfiles missing"

echo "[INFO] personal skill lock smoke test passed"

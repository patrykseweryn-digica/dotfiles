#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${DOTFILES_DIR}/.agents/skill-lock.json"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

locked=$'anki-export\tskills/learning/anki-export/SKILL.md
crawlee-build\tskills/scraping/crawlee-build/SKILL.md
generate-flashcards\tskills/learning/generate-flashcards/SKILL.md
hook-setup\tskills/engineering/hook-setup/SKILL.md
kolbs-reflection\tskills/learning/kolbs-reflection/SKILL.md
mlflow-analyzer\tskills/engineering/mlflow-analyzer/SKILL.md
obsidian-notes\tskills/productivity/obsidian-notes/SKILL.md
plain-talk\tskills/productivity/plain-talk/SKILL.md
project-statement\tskills/engineering/project-statement/SKILL.md
scrapy-build\tskills/scraping/scrapy-build/SKILL.md
scrapy-deploy\tskills/scraping/scrapy-deploy/SKILL.md
show-the-change\tskills/engineering/show-the-change/SKILL.md
web-scraping-ops\tskills/scraping/web-scraping-ops/SKILL.md
web-scraping-pipeline-design\tskills/scraping/web-scraping-pipeline-design/SKILL.md
web-scraping-references\tskills/scraping/web-scraping-references/SKILL.md
web-scraping-scout\tskills/scraping/web-scraping-scout/SKILL.md
web-scraping-simple\tskills/scraping/web-scraping-simple/SKILL.md
write-digica-readme\tskills/engineering/write-digica-readme/SKILL.md'

removed=(
    web-scraping-audit
    web-scraping-debug
)

kept=(
    ask-matt
    last30days
    design-control-loop
)

personal_count=0
while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    personal_count=$((personal_count + 1))
    [ ! -e "${DOTFILES_DIR}/.agents/skills-custom/${name}" ] ||
        fail "personal skill still copied in skills-custom: ${name}"
    jq -e --arg name "$name" --arg path "$path" '
        .skills[$name] as $skill |
        $skill.source == "p-severin/skills" and
        $skill.sourceType == "github" and
        $skill.sourceUrl == "https://github.com/p-severin/skills.git" and
        $skill.skillPath == $path and
        ($skill | keys) == ["skillPath", "source", "sourceType", "sourceUrl"] and
        ($skill.ref | not)
    ' "$LOCK" >/dev/null ||
        fail "personal skill lock entry is wrong: ${name}"
done <<<"$locked"
[ "$personal_count" -eq 18 ] ||
    fail "personal skill lock must list 18 skills, got ${personal_count}"

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

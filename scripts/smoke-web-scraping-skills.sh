#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="${DOTFILES_DIR}/.agents/skill-lock.json"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

locked=$'anki-flashcards\tskills/learning/anki-flashcards/SKILL.md
crawlee-build\tskills/scraping/crawlee-build/SKILL.md
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
    anki-export
    generate-flashcards
    web-scraping-audit
    web-scraping-debug
)

# Former repository copies now track their upstream source.
kept=(
    $'ask-matt\tmattpocock/skills'
    $'last30days\tmvanhorn/last30days-skill'
    $'design-control-loop\thumanlayer/skills'
)

personal_count=0
while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    personal_count=$((personal_count + 1))
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
[ "$personal_count" -eq 17 ] ||
    fail "personal skill lock must list 17 skills, got ${personal_count}"

for name in "${removed[@]}"; do
    jq -e --arg name "$name" '.skills[$name] | not' "$LOCK" >/dev/null ||
        fail "removed skill still locked: ${name}"
done

for entry in "${kept[@]}"; do
    IFS=$'\t' read -r name source <<<"$entry"
    jq -e --arg name "$name" --arg source "$source" '
        .skills[$name].source == $source
    ' "$LOCK" >/dev/null || fail "upstream skill not locked: ${name}"
done

[ ! -e "${DOTFILES_DIR}/.agents/skills-custom" ] ||
    fail "skills must come from upstream lock entries, not repository copies"

[ -f "${DOTFILES_DIR}/.agents/skills/verify-dotfiles/SKILL.md" ] ||
    fail "verify-dotfiles missing"

echo "[INFO] personal skill lock smoke test passed"

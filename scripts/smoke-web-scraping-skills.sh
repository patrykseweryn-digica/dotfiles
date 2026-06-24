#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

require_file() {
    [ -f "${DOTFILES_DIR}/$1" ] || fail "missing file: $1"
}

require_text() {
    local file="$1"
    local expected="$2"

    grep -F "$expected" "${DOTFILES_DIR}/${file}" >/dev/null 2>&1 || fail "missing '${expected}' in ${file}"
}

require_frontmatter() {
    python3 - "$@" <<'PY'
import re
import sys
from pathlib import Path

import yaml

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\n(.*?)\n---", text, re.DOTALL)
    if not match:
        raise SystemExit(f"missing frontmatter: {path}")
    yaml.safe_load(match.group(1))
PY
}

skills=(
    ".agents/skills-custom/web-scraping-scout/SKILL.md"
    ".agents/skills-custom/web-scraping-simple/SKILL.md"
    ".agents/skills-custom/web-scraping-pipeline-design/SKILL.md"
    ".agents/skills-custom/scrapy-build/SKILL.md"
    ".agents/skills-custom/crawlee-build/SKILL.md"
    ".agents/skills-custom/web-scraping-audit/SKILL.md"
    ".agents/skills-custom/web-scraping-debug/SKILL.md"
    ".agents/skills-custom/scrapy-deploy/SKILL.md"
    ".agents/skills-custom/web-scraping-references/SKILL.md"
)

for skill in "${skills[@]}"; do
    require_file "$skill"
done
require_frontmatter "${skills[@]/#/${DOTFILES_DIR}/}"

require_file ".agents/skills-custom/web-scraping-references/references/lifecycle.md"
require_file ".agents/skills-custom/web-scraping-references/references/feasibility-poc.md"
require_file ".agents/skills-custom/web-scraping-references/references/framework-choice.md"
require_file ".agents/skills-custom/web-scraping-references/references/storage-policy.md"
require_file ".agents/skills-custom/web-scraping-references/references/quality-gates.md"
require_file ".agents/skills-custom/web-scraping-references/references/legal-ethics.md"
require_file ".agents/skills-custom/web-scraping-references/references/operator-runbook.md"
require_file ".agents/skills-custom/web-scraping-references/references/downstream-ml-llm.md"
require_file ".agents/skills-custom/web-scraping-references/references/toolbox.md"
require_file ".agents/skills-custom/web-scraping-references/references/checkpointing.md"

scout=".agents/skills-custom/web-scraping-scout/SKILL.md"
require_text "$scout" "One-off feasibility or small API/HTML/browser-backed proof: use \`web-scraping-simple\`."
require_text "$scout" "Recurring, production, long-running, or operational scraper: use \`web-scraping-pipeline-design\`."
require_text "$scout" "Existing scraper broken or output empty: use \`web-scraping-debug\`."
require_text "$scout" "Need output quality review: use \`web-scraping-audit\`."
require_text "$scout" "Deploying, Dockerizing, scheduling, or monitoring an existing Scrapy project: use \`scrapy-deploy\`."
require_text "$scout" "GraphQL discovery"
require_text "$scout" "Ask before login/session reuse"

pipeline=".agents/skills-custom/web-scraping-pipeline-design/SKILL.md"
for section in \
    "### Target" \
    "### Goal/Data Contract" \
    "### Source Strategy" \
    "### Framework Decision" \
    "### Why Not Alternatives" \
    "### Data Lifecycle" \
    "### Storage/Formats" \
    "### Run Modes" \
    "### Quality Gates/Audit" \
    "### Risk Notes" \
    "### Deploy/Operations" \
    "### Open Questions" \
    "### Approval Request"; do
    require_text "$pipeline" "$section"
done
require_text "$pipeline" "Stop after the design brief and ask for approval before implementation handoff."

simple=".agents/skills-custom/web-scraping-simple/SKILL.md"
require_text "$simple" "structured feasibility PoC"
require_text "$simple" "FEASIBILITY.md"
require_text "$simple" "raw/failure evidence"

scrapy=".agents/skills-custom/scrapy-build/SKILL.md"
require_text "$scrapy" "Scrapy is the default production implementation path"
require_text "$scrapy" "smoke/sample mode and full mode"
require_text "$scrapy" "manifest, parsed output, curated output, audit output"

crawlee=".agents/skills-custom/crawlee-build/SKILL.md"
require_text "$crawlee" "browser-context-heavy"
require_text "$crawlee" "Do not use Crawlee as the default for ordinary HTTP/API/listing-detail production scraping"
require_text "$crawlee" "SPA interaction-heavy"

audit=".agents/skills-custom/web-scraping-audit/SKILL.md"
require_text "$audit" "Audit runs, not just files."
require_text "$audit" "Compare to a previous good run"
require_text "$audit" "trusted, suspicious, or blocked"

debug=".agents/skills-custom/web-scraping-debug/SKILL.md"
require_text "$debug" "Prefer replay before live refetching."
require_text "$debug" "fetch failure"
require_text "$debug" "validation/schema drift"

deploy=".agents/skills-custom/scrapy-deploy/SKILL.md"
require_text "$deploy" "Keep this Scrapy-specific"
require_text "$deploy" "cron/systemd"
require_text "$deploy" "Retention Notes"
require_text "$deploy" "optional alerts are skipped cleanly"

quality=".agents/skills-custom/web-scraping-references/references/quality-gates.md"
for scenario in \
    "static HTML feasibility and production" \
    "API/XHR feasibility and production" \
    "listing-detail crawl" \
    "SPA with discoverable API" \
    "occasional render" \
    "interaction-heavy SPA" \
    "login/captcha/anti-bot risk" \
    "existing broken scraper" \
    "existing production audit" \
    "Scrapy deployment"; do
    require_text "$quality" "$scenario"
done

echo "[INFO] web scraping skill smoke test passed"

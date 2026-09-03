#!/usr/bin/env bash
set -u

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .toolInput.command // .command // ""' 2>/dev/null)
else
  COMMAND=$(INPUT="$INPUT" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("INPUT", "{}") or "{}")
tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
print(tool_input.get("command") or payload.get("command") or "")
PY
)
fi

if [ -z "${COMMAND:-}" ]; then
  exit 0
fi

GIT_WITH_OPTIONS='(^|[;&|[:space:]])git([[:space:]]+(-C[[:space:]]+[^;&|[:space:]]+|-c[[:space:]]+[^;&|[:space:]]+|--git-dir=[^;&|[:space:]]+|--work-tree=[^;&|[:space:]]+))*[[:space:]]+'

PATTERN_LABELS=(
  "git push"
  "git reset --hard"
  "git clean --force"
  "git branch --delete --force"
  "git checkout ."
  "git restore ."
  "push --force"
  "reset --hard"
)

PATTERN_REGEXES=(
  "${GIT_WITH_OPTIONS}push([[:space:]]|$)"
  "${GIT_WITH_OPTIONS}reset([^;&|]*[[:space:]])--hard([=[:space:]]|$)"
  "${GIT_WITH_OPTIONS}clean([^;&|]*[[:space:]])(-[^[:space:]]*f[^[:space:]]*|--force)([[:space:]]|$)"
  "${GIT_WITH_OPTIONS}branch([^;&|]*[[:space:]])(-D|--delete[[:space:]]+--force|--force[[:space:]]+--delete)([[:space:]]|$)"
  "${GIT_WITH_OPTIONS}checkout([^;&|]*[[:space:]])(--[[:space:]]+)?\\.([[:space:]]|$)"
  "${GIT_WITH_OPTIONS}restore([^;&|]*[[:space:]])(--[[:space:]]+)?\\.([[:space:]]|$)"
  '(^|[;&|[:space:]])push[[:space:]]+--force([[:space:]]|$)'
  '(^|[;&|[:space:]])reset[[:space:]]+--hard([=[:space:]]|$)'
)

for i in "${!PATTERN_REGEXES[@]}"; do
  pattern=${PATTERN_REGEXES[$i]}
  if printf '%s\n' "$COMMAND" | grep -Eq "$pattern"; then
    echo "BLOCKED: '$COMMAND' matches dangerous git operation '${PATTERN_LABELS[$i]}'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

exit 0

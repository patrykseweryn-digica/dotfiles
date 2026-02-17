#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

# Context bar color based on usage
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="█"; done
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))
COST_FMT=$(LC_NUMERIC=C printf '$%.2f' "$COST")

# Git branch with caching
CACHE_FILE="/tmp/statusline-git-cache-$(echo "$DIR" | md5sum | cut -d' ' -f1)"
CACHE_MAX_AGE=5

cache_is_stale() {
    [ ! -f "$CACHE_FILE" ] || \
    [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

BRANCH=""
if cache_is_stale; then
    if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
        BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
        STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        echo "$BRANCH|$STAGED|$MODIFIED" > "$CACHE_FILE"
    else
        echo "||" > "$CACHE_FILE"
    fi
fi

IFS='|' read -r BRANCH STAGED MODIFIED < "$CACHE_FILE"

GIT_INFO=""
if [ -n "$BRANCH" ]; then
    GIT_INFO=" | 🌿 $BRANCH"
    [ "$STAGED" -gt 0 ] 2>/dev/null && GIT_INFO="${GIT_INFO} ${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] 2>/dev/null && GIT_INFO="${GIT_INFO} ${YELLOW}~${MODIFIED}${RESET}"
fi

echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}${GIT_INFO}"
echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET} | ⏱️ ${MINS}m ${SECS}s"

# Herdr writes its Claude hook with an absolute path and does not recognize
# the portable entry. Keep one Herdr hook that resolves through $HOME.
def normalize_herdr_hook:
    def is_herdr: (.command? // "") | contains("herdr-agent-state.sh");
    if (.hooks.SessionStart | type) == "array" then
        (.hooks.SessionStart[].hooks[]? |
            select(.type == "command" and is_herdr)).command =
            "bash \"$HOME/.claude/hooks/herdr-agent-state.sh\" session" |
        .hooks.SessionStart |= (
            reduce .[] as $entry ({items: [], seen_herdr: false};
                (($entry.hooks // []) | any(is_herdr)) as $herdr |
                if $herdr and .seen_herdr then
                    .
                else
                    .items += [$entry] |
                    if $herdr then .seen_herdr = true else . end
                end
            ) | .items
        )
    else . end;

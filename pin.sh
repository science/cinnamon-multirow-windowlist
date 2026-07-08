#!/bin/bash
# Pin a window to a fixed taskbar position.
#
# Usage:
#   ./pin.sh <app> [title-regex] [priority]   Pin app with optional title filter and priority
#   ./pin.sh --list                            Show current pin rules
#   ./pin.sh --clear                           Remove all pin rules
#   ./pin.sh --remove <index>                  Remove rule by index (from --list)
#   ./pin.sh --apps                            List running apps and their IDs
#
# Examples:
#   ./pin.sh terminal                    Pin all Terminal windows (auto-priority)
#   ./pin.sh firefox "^Mail -" 0         Pin Firefox Mail at position 0 (leftmost)
#   ./pin.sh firefox "^Calendar -" 1     Pin Firefox Calendar at position 1
#   ./pin.sh bash "^claude"              Pin claude terminal (auto-priority)
#
# Priority: 0 = leftmost (highest priority). Lower number = further left.
# If omitted, auto-assigns the next available slot after existing rules.

set -eo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
APPLET_UUID="multirow-window-list@science"
CONFIG_DIR="$HOME/.config/cinnamon/spices/$APPLET_UUID"
EVAL_HELPER="/tmp/cinnamon-eval.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# --- Ensure eval helper exists ---
ensure_eval_helper() {
    [[ -f "$EVAL_HELPER" ]] && return
    cat > "$EVAL_HELPER" << 'PYEOF'
#!/usr/bin/env python3
import subprocess, sys, re
js = sys.stdin.read().strip()
result = subprocess.run(
    ["dbus-send", "--session", "--print-reply", "--dest=org.Cinnamon",
     "/org/Cinnamon", "org.Cinnamon.Eval", "string:" + js],
    capture_output=True, text=True)
output = result.stdout
match = re.search(r'^\s*string "(.*)"$', output, re.MULTILINE)
if match:
    val = match.group(1)
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if "boolean true" in output else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
PYEOF
}

# --- Find the instance config file ---
find_config_file() {
    local files
    files=$(ls "$CONFIG_DIR"/*.json 2>/dev/null)
    if [[ -z "$files" ]]; then
        echo ""
        return
    fi
    # If multiple instances, use the first one
    echo "$files" | head -1
}

# --- Get current rules as JSON array ---
get_rules() {
    local config
    config=$(find_config_file)
    if [[ -z "$config" ]]; then
        echo "[]"
        return
    fi
    python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
val = data.get('pin-rules', {}).get('value', '[]')
# value is a JSON string containing an array
if isinstance(val, str):
    arr = json.loads(val)
else:
    arr = val
print(json.dumps(arr))
" "$config"
}

# --- Write rules back to config file ---
write_rules() {
    local json_array="$1"
    local config
    config=$(find_config_file)
    if [[ -z "$config" ]]; then
        echo -e "${RED}ERROR: No applet config file found in $CONFIG_DIR${NC}" >&2
        exit 1
    fi
    python3 -c "
import sys, json
config_path = sys.argv[1]
new_rules = sys.argv[2]
with open(config_path) as f:
    data = json.load(f)
data['pin-rules']['value'] = new_rules
with open(config_path, 'w') as f:
    json.dump(data, f, indent=4)
" "$config" "$json_array"
}

# --- Get next priority ---
next_priority() {
    local rules="$1"
    python3 -c "
import sys, json
rules = json.loads(sys.argv[1])
if not rules:
    print(0)
else:
    print(max(r['priority'] for r in rules) + 1)
" "$rules"
}

# --- List running apps ---
list_apps() {
    ensure_eval_helper
    local raw
    raw=$(echo '
var _actors = global.get_window_actors();
var _tracker = imports.gi.Cinnamon.WindowTracker.get_default();
var _r = [];
for (var _i = 0; _i < _actors.length; _i++) {
    var _w = _actors[_i].get_meta_window();
    if (!_w) continue;
    var _app = _tracker.get_window_app(_w);
    if (!_app) continue;
    _r.push(_app.get_id() + " | " + (_w.get_title() || "").substring(0, 60));
}
_r.join("\n");
' | python3 "$EVAL_HELPER")
    # The D-Bus eval returns literal \n — convert to real newlines
    echo "$raw" | sed 's/\\n/\n/g'
}

# --- Fuzzy match app name to app ID ---
# Searches running windows for an app ID containing the search term
resolve_app_id() {
    local search="$1"
    ensure_eval_helper
    local apps
    apps=$(list_apps)
    if [[ -z "$apps" ]]; then
        echo ""
        return
    fi
    # Find matching app IDs (case-insensitive grep on app ID and title)
    local matches
    matches=$(echo "$apps" | grep -i "$search" | cut -d'|' -f1 | sed 's/ *$//' | sort -u)
    local count
    count=$(echo "$matches" | grep -c . || true)

    if [[ $count -eq 0 ]]; then
        echo ""
    elif [[ $count -eq 1 ]]; then
        echo "$matches"
    else
        # Multiple matches — show them and let user pick
        echo -e "${YELLOW}Multiple apps match '$search':${NC}" >&2
        local i=1
        while IFS= read -r app_id; do
            local titles
            titles=$(echo "$apps" | grep "^$app_id" | head -2 | cut -d'|' -f2 | sed 's/^ *//')
            echo -e "  ${BOLD}$i)${NC} $app_id — $titles" >&2
            i=$((i + 1))
        done <<< "$matches"
        echo -n "Pick [1-$count]: " >&2
        read -r choice
        echo "$matches" | sed -n "${choice}p"
    fi
}

# ============================================================
# Main
# ============================================================

case "${1:-}" in
    --list|-l)
        rules=$(get_rules)
        count=$(echo "$rules" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))")
        if [[ "$count" == "0" ]]; then
            echo "No pin rules configured."
            exit 0
        fi
        echo -e "${BOLD}Pin Rules:${NC}"
        python3 -c "
import sys, json
rules = json.loads(sys.stdin.read())
for i, r in enumerate(rules):
    title = r.get('title', '(any title)')
    print(f'  {i}) priority={r[\"priority\"]}  app={r[\"appId\"]}  title={title}')
" <<< "$rules"
        ;;

    --clear)
        write_rules "[]"
        echo -e "${GREEN}All pin rules cleared.${NC}"
        ;;

    --remove|-r)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 --remove <index>"
            echo "Run '$0 --list' to see indices."
            exit 1
        fi
        rules=$(get_rules)
        new_rules=$(python3 -c "
import sys, json
rules = json.loads(sys.argv[1])
idx = int(sys.argv[2])
if 0 <= idx < len(rules):
    removed = rules.pop(idx)
    print(json.dumps(rules))
else:
    print('ERROR', file=sys.stderr)
    sys.exit(1)
" "$rules" "$2")
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Invalid index: $2${NC}"
            exit 1
        fi
        write_rules "$new_rules"
        echo -e "${GREEN}Removed rule $2.${NC}"
        bash "$SELF" --list
        ;;

    --apps|-a)
        ensure_eval_helper
        echo -e "${BOLD}Running apps:${NC}"
        list_apps | while IFS='|' read -r app_id title; do
            echo -e "  ${CYAN}$(echo "$app_id" | sed 's/ *$//')${NC} — $title"
        done
        ;;

    --help|-h|"")
        echo "Usage: $0 <app> [title-regex] [priority]"
        echo "       $0 --list | --clear | --remove <idx> | --apps"
        echo ""
        echo "Priority: 0 = leftmost. Lower number = further left. Auto-assigned if omitted."
        echo ""
        echo "Examples:"
        echo "  $0 terminal                    Pin all Terminal windows (auto-priority)"
        echo "  $0 firefox \"^Mail -\" 0         Pin Firefox Mail at leftmost position"
        echo "  $0 firefox \"^Calendar -\" 1     Pin Firefox Calendar second from left"
        echo "  $0 bash \"^claude\"              Pin terminal running claude"
        echo "  $0 --list                       Show current pin rules"
        echo "  $0 --apps                       List running apps and their IDs"
        exit 0
        ;;

    -*)
        echo -e "${RED}Unknown option: $1${NC}"
        bash "$SELF" --help
        exit 1
        ;;

    *)
        # --- Pin a window ---
        SEARCH="$1"
        TITLE_REGEX="${2:-}"
        EXPLICIT_PRIORITY="${3:-}"

        APP_ID=$(resolve_app_id "$SEARCH")
        if [[ -z "$APP_ID" ]]; then
            echo -e "${RED}No running app matches '$SEARCH'${NC}"
            echo "Run '$0 --apps' to see running apps."
            exit 1
        fi

        rules=$(get_rules)
        if [[ -n "$EXPLICIT_PRIORITY" ]]; then
            if ! [[ "$EXPLICIT_PRIORITY" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Priority must be a non-negative integer, got: $EXPLICIT_PRIORITY${NC}"
                exit 1
            fi
            priority="$EXPLICIT_PRIORITY"
        else
            priority=$(next_priority "$rules")
        fi

        # Build the new rule
        if [[ -n "$TITLE_REGEX" ]]; then
            # Validate the regex
            if ! python3 -c "import re, sys; re.compile(sys.argv[1])" "$TITLE_REGEX" 2>/dev/null; then
                echo -e "${RED}Invalid regex: $TITLE_REGEX${NC}"
                exit 1
            fi
            new_rule="{\"appId\":\"$APP_ID\",\"title\":\"$TITLE_REGEX\",\"priority\":$priority}"
        else
            new_rule="{\"appId\":\"$APP_ID\",\"priority\":$priority}"
        fi

        # Append to rules
        new_rules=$(python3 -c "
import sys, json
rules = json.loads(sys.argv[1])
new = json.loads(sys.argv[2])
rules.append(new)
print(json.dumps(rules))
" "$rules" "$new_rule")

        write_rules "$new_rules"

        echo -e "${GREEN}Pinned!${NC}"
        echo -e "  App:      ${BOLD}$APP_ID${NC}"
        if [[ -n "$TITLE_REGEX" ]]; then
            echo -e "  Title:    $TITLE_REGEX"
        else
            echo -e "  Title:    (any)"
        fi
        echo -e "  Priority: $priority (lower = further left)"
        echo ""
        bash "$SELF" --list
        ;;
esac

#!/bin/bash
# applet-eval.sh — D-Bus eval library for systray-overflow E2E tests.
#
# Sources into test scripts. Provides functions to query applet state,
# open/close popup, get icon positions, and take screenshots.
#
# Requires: vm_ssh, vm_run, get_vm_ip functions (from test harness)
#           cinnamon-eval.py installed on VM (install_eval_helper)

# --- JS boilerplate to find our applet instance ---
# Walks Main.panelManager.panels looking for _registry (our signature).
# Uses index-based loop because for...of over GJS arrays with null entries
# silently fails in Cinnamon D-Bus Eval.
FIND_APPLET_JS='
const Main = imports.ui.main;
let _a = null;
for (let _i = 0; _i < Main.panelManager.panels.length; _i++) {
    let p = Main.panelManager.panels[_i];
    if (!p) continue;
    for (let z of [p._rightBox, p._leftBox, p._centerBox]) {
        for (let c of z.get_children()) {
            if (c._delegate && c._delegate._registry)
                _a = c._delegate;
        }
    }
}
'

# --- Core eval function ---
# eval_js "javascript expression" → prints result string
eval_js() {
    local js="$1"
    echo "$js" | vm_ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
}

# --- Applet state ---
# Returns JSON: { managedCount, popupOpen, chevronVisible, popupHeight }
applet_state() {
    eval_js "${FIND_APPLET_JS}
if (!_a) JSON.stringify({error: 'applet not found'});
else JSON.stringify({
    managedCount: _a._registry ? _a._registry.size : 0,
    popupOpen: _a._popup ? _a._popup.isOpen() : false,
    chevronVisible: _a._popup && _a._popup.overflowIndicator ? _a._popup.overflowIndicator.visible : false,
    popupHeight: (_a._popup && _a._popup.panel && _a._popup.panel.visible) ? _a._popup.panel.height : 0,
    popupWidth: (_a._popup && _a._popup.panel && _a._popup.panel.visible) ? _a._popup.panel.width : 0
});
"
}

# --- Popup section counts ---
# Returns JSON: { visible: N, overflow: N, inactive: N }
popup_section_counts() {
    eval_js "${FIND_APPLET_JS}
if (!_a || !_a._popup) JSON.stringify({error: 'no popup'});
else JSON.stringify({
    visible: _a._popup.visibleSection ? _a._popup.visibleSection.get_n_children() : 0,
    overflow: _a._popup.overflowSection ? _a._popup.overflowSection.get_n_children() : 0,
    inactive: _a._popup.inactiveSection ? _a._popup.inactiveSection.get_n_children() : 0
});
"
}

# --- Icon positions in a section ---
# icon_positions "visible"|"overflow"|"inactive" → JSON array of {x, y}
icon_positions() {
    local section="$1"
    local prop
    case "$section" in
        visible) prop="visibleSection" ;;
        overflow) prop="overflowSection" ;;
        inactive) prop="inactiveSection" ;;
        *) echo '{"error":"bad section"}'; return 1 ;;
    esac

    eval_js "${FIND_APPLET_JS}
if (!_a || !_a._popup || !_a._popup.${prop}) JSON.stringify([]);
else {
    let s = _a._popup.${prop};
    let result = [];
    for (let i = 0; i < s.get_n_children(); i++) {
        let c = s.get_child_at_index(i);
        let [x, y] = c.get_transformed_position();
        result.push({x: Math.round(x), y: Math.round(y)});
    }
    JSON.stringify(result);
}
"
}

# --- Popup open/close ---
popup_open() {
    eval_js "${FIND_APPLET_JS}
if (_a && _a._popup && !_a._popup.isOpen()) _a._popup.openPanel();
'ok';
"
}

popup_close() {
    eval_js "${FIND_APPLET_JS}
if (_a && _a._popup && _a._popup.isOpen()) _a._popup.closePanel();
'ok';
"
}

# --- DND handler state ---
dnd_state() {
    eval_js "${FIND_APPLET_JS}
if (!_a || !_a._dndHandler) JSON.stringify({error: 'no dnd handler'});
else JSON.stringify({
    state: _a._dndHandler.state,
    isDragging: _a._dndHandler.isDragging(),
    isActive: _a._dndHandler.isActive()
});
"
}

# --- Get chevron position ---
chevron_position() {
    eval_js "${FIND_APPLET_JS}
if (!_a || !_a._popup || !_a._popup.overflowIndicator) JSON.stringify({error: 'no chevron'});
else {
    let c = _a._popup.overflowIndicator;
    let [x, y] = c.get_transformed_position();
    let [w, h] = c.get_transformed_size();
    JSON.stringify({x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h)});
}
"
}

# --- Get popup panel bounds ---
popup_bounds() {
    eval_js "${FIND_APPLET_JS}
if (!_a || !_a._popup || !_a._popup.panel) JSON.stringify({error: 'no panel'});
else {
    let p = _a._popup.panel;
    let [x, y] = p.get_transformed_position();
    let [w, h] = p.get_transformed_size();
    JSON.stringify({x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h)});
}
"
}

# --- Screenshot ---
# screenshot [label] → saves to test/screenshots/e2e-{label}.png
screenshot() {
    local label="${1:-shot}"
    local filename="e2e-${label}.png"
    mkdir -p "$SCREENSHOT_DIR"
    vm_run "xwd -root -silent | convert xwd:- png:/tmp/screenshot.png" 2>/dev/null || return 1
    scp $SSH_OPTS "steve@$(get_vm_ip):/tmp/screenshot.png" "$SCREENSHOT_DIR/$filename" 2>/dev/null || return 1
    echo "$SCREENSHOT_DIR/$filename"
}

# --- XTest actions wrapper ---
# Uses the python XTest tool on the VM via host mount
XTEST_PY="/mnt/host-dev/cinnamon-systray-overflow/vm/test-tools/xtest-actions.py"

xtest_click() {
    local x="$1" y="$2" button="${3:-1}"
    vm_run "python3 $XTEST_PY click $x $y --button=$button"
}

xtest_drag() {
    local sx="$1" sy="$2" ex="$3" ey="$4" steps="${5:-10}"
    vm_run "python3 $XTEST_PY drag $sx $sy $ex $ey --steps=$steps"
}

xtest_key() {
    local keysym="$1"
    vm_run "python3 $XTEST_PY key $keysym"
}

xtest_move() {
    local x="$1" y="$2"
    vm_run "python3 $XTEST_PY move $x $y"
}

# --- JSON field helper ---
json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['$field'])"
}

# --- JSON array length ---
json_array_len() {
    local json="$1"
    echo "$json" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))"
}

# --- JSON array element field ---
json_array_field() {
    local json="$1"
    local index="$2"
    local field="$3"
    echo "$json" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())[$index]['$field'])"
}

#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1 — $2"; }

assert_contains() {
    local description="$1" pattern="$2" file="$3"
    if grep -Fq "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description" "missing '$pattern' in $file"
    fi
}

echo "plugin.json"
python3 - <<'PY' \
    && pass "valid manifest" \
    || fail "manifest" "invalid JSON or metadata"
import json
import re

with open("plugin.json", encoding="utf-8") as handle:
    plugin = json.load(handle)

assert plugin["id"] == "dankDisplayControl"
assert plugin["type"] == "widget"
assert "dankbar-widget" in plugin["capabilities"]
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", plugin["version"])
assert "process" in plugin["permissions"]
PY

COMPONENT="$(python3 -c 'import json; print(json.load(open("plugin.json"))["component"].removeprefix("./"))')"
SETTINGS="$(python3 -c 'import json; print(json.load(open("plugin.json"))["settings"].removeprefix("./"))')"

for file in "$COMPONENT" "$SETTINGS"; do
    if [ -f "$file" ]; then
        pass "$file exists"
    else
        fail "$file" "referenced file does not exist"
    fi
done

assert_contains "component plugin id" 'property var pluginService' "$COMPONENT"
assert_contains "settings plugin id" 'pluginId: "dankDisplayControl"' "$SETTINGS"
assert_contains "Hyprland effective state" '["hyprctl", "-j", "monitors", "all"]' "$COMPONENT"
assert_contains "software mirror detection" 'Couch mirror ' "$COMPONENT"
assert_contains "couch width" 'popoutWidth: 520' "$COMPONENT"
assert_contains "effective state section" 'text: "Now showing"' "$COMPONENT"
assert_contains "action section" 'text: "Quick actions"' "$COMPONENT"
assert_contains "policy section" 'text: "Layout policy"' "$COMPONENT"

for layout in adaptive all dual-tvs primary-aux secondary-aux solo-primary solo-secondary solo-tertiary; do
    assert_contains "layout $layout" "{ id: \"$layout\"" "$COMPONENT"
done

for command in couch-display-layout couch-display-mirror couch-audio-output; do
    assert_contains "command $command" "\"$command\"" "$COMPONENT"
done

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

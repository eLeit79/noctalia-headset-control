#!/usr/bin/env bash
#
# Exercise Main.qml's failure handling without touching the running shell.
#
#   ./test/runtime.sh
#
# run.sh restarts noctalia-shell to test capability gating through the real UI. This one
# does not: it loads Main.qml on its own under `qs -p`, with a stub headsetcontrol that can
# be made to fail on demand, and asserts the state Main.qml ends up in. Nothing is
# installed, no shell is killed, and your headset is never touched.
#
# These paths are the reason it exists: each of them looks exactly like a working plugin
# from the outside, and none of them can be produced by the capability stub.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
main="$here/../headset-control/Main.qml"
[ -f "$main" ] || { echo "runtime.sh: cannot find Main.qml at $main" >&2; exit 1; }
command -v qs >/dev/null || { echo "runtime.sh: qs (Quickshell) is not on PATH" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# Main.qml imports noctalia's Logger, which does not exist outside the shell. Swap it for
# console output so the file can run under bare `qs -p`; nothing else is changed, so what
# is under test really is the shipped code.
sed -e '/^import qs\.Commons$/d' \
    -e 's/Logger\.w(/console.log("WARN",/g' -e 's/Logger\.i(/console.log("INFO",/g' \
    -e 's/Logger\.d(/console.log("DEBUG",/g' -e 's/Logger\.e(/console.log("ERROR",/g' \
    "$main" > "$tmp/Main.qml"
# A binary that is not there at all cannot be stubbed, only named.
sed 's/"headsetcontrol"/"headsetcontrol-absent-for-tests"/g' "$tmp/Main.qml" > "$tmp/MainMissing.qml"

cat > "$tmp/bin/headsetcontrol" <<'STUB'
#!/bin/sh
case "$*" in
  *-b*json*)
    [ "${STUB_EMPTY:-0}" = 1 ] && exit 0            # present, but prints nothing
    if [ -n "${STUB_HANG_ONCE:-}" ] && [ ! -f "$STUB_HANG_ONCE" ]; then
      touch "$STUB_HANG_ONCE"; trap '' TERM; sleep 60   # hung, and deaf to SIGTERM
    fi
    cat "$STUB_JSON" ;;
  *)
    [ -n "${STUB_SET_SLEEP:-}" ] && sleep "$STUB_SET_SLEEP"
    exit "${STUB_SET_EXIT:-0}" ;;
esac
exit 0
STUB
chmod +x "$tmp/bin/headsetcontrol"
cp "$here/scenarios/1-full.json" "$tmp/dev.json"

# $1 type to load, $2 initial settings, $3 body (timers), $4 seconds to run
write_case() {
  cat > "$tmp/case.qml" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  QtObject {
    id: api
    property var pluginSettings: ($2)
    property int translationVersion: 0
    // PluginService replaces the whole object on save so bindings re-evaluate; mimic it.
    function saveSettings() { var c = {}; for (var k in pluginSettings) c[k] = pluginSettings[k]; pluginSettings = c; }
    function tr(k) { return k; }
  }
  $1 { id: m; pluginApi: api }
  $3
  Timer { interval: $4 * 1000; running: true; onTriggered: {
    console.log("RESULT toolAvailable=" + m.toolAvailable + " deviceFound=" + m.deviceFound
      + " sidetone=" + m.sidetone + " controlsApplied=" + m.controlsApplied
      + " level=" + m.batteryLevel);
    Qt.quit();
  } }
}
EOF
}

fail=0
# $1 name, $2 expected substring of the RESULT line, $3.. env assignments
run_case() {
  local name="$1" want="$2"; shift 2
  local out
  out="$(env "$@" STUB_JSON="$tmp/dev.json" PATH="$tmp/bin:$PATH" \
        timeout 60 qs -p "$tmp/case.qml" 2>&1 | tr -d '\r' | grep -a "RESULT" | tail -1 || true)"
  out="${out#*RESULT }"
  if [ -z "$out" ]; then
    printf '  FAIL  %-22s (no result; qs produced nothing)\n' "$name"; fail=1; return
  fi
  case "$out" in
    *"$want"*) printf '  ok    %-22s %s\n' "$name" "$out" ;;
    *)         printf '  FAIL  %-22s\n        wanted: %s\n        got:    %s\n' "$name" "$want" "$out"; fail=1 ;;
  esac
}

echo "runtime checks (no shell restart, real headset untouched)"

# A working tool and a real device: the baseline the others are read against.
write_case Main '{}' '' 4
run_case "healthy poll" "deviceFound=true"

# The binary is missing. Quickshell emits neither exited nor streamFinished for that, so
# every failure path built on those signals has to be reached some other way.
write_case MainMissing '{ "sidetone": 0, "controlsApplied": false }' \
  'Timer { interval: 500; running: true; onTriggered: m.applySidetoneEnabled(true) }' 6
run_case "missing binary" "toolAvailable=false deviceFound=false sidetone=0 controlsApplied=false"

# Present but silent. A working headsetcontrol always prints JSON, even with no device.
write_case Main '{}' '' 6
run_case "empty stdout" "toolAvailable=false" STUB_EMPTY=1

# A setter that genuinely fails must put the persisted value back.
write_case Main '{ "sidetone": 0, "controlsApplied": false }' \
  'Timer { interval: 600; running: true; onTriggered: m.applySidetoneEnabled(true) }' 4
run_case "setter exits 3" "sidetone=0 controlsApplied=false" STUB_SET_EXIT=3

# Two applies inside one command's runtime: killing the first must not revert the second.
write_case Main '{ "sidetone": 0, "controlsApplied": false }' \
  'Timer { interval: 600; running: true; onTriggered: m.applySidetoneEnabled(true) }
   Timer { interval: 800; running: true; onTriggered: m.applySidetoneEnabled(false) }' 5
run_case "double apply" "sidetone=0" STUB_SET_SLEEP=0.5

# A poll that hangs and ignores SIGTERM must not latch polling off forever, and its
# empty output must not be mistaken for a missing tool.
rm -f "$tmp/hung.marker"
write_case Main '{ "pollIntervalSeconds": 600 }' \
  'Timer { interval: 19000; running: true; onTriggered: m.refresh() }' 24
run_case "hung poll recovers" "toolAvailable=true deviceFound=true" STUB_HANG_ONCE="$tmp/hung.marker"

[ "$fail" = 0 ] || { echo; echo "runtime.sh: failures above" >&2; exit 1; }
echo "all runtime checks passed"

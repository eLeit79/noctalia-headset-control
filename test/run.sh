#!/usr/bin/env bash
#
# Cycle every capability scenario past the running plugin and print the state it derives.
#
# This RESTARTS noctalia-shell with the stub headsetcontrol on PATH and NOCTALIA_DEBUG=1
# (the state line is logged at debug level). Your real headset is not touched: the stub
# swallows every setter. The bar will show simulated devices until you restore the shell,
# which the script tells you how to do at the end.
set -euo pipefail
fail=0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log=/tmp/noctalia.log

state_count() { grep "HeadsetControl" "$log" 2>/dev/null | grep -c "state " || true; }
last_state() { grep "HeadsetControl" "$log" 2>/dev/null | grep "state " | tail -1 | sed 's/.*state //'; }

# The scenario file is swapped under a running shell, so write it somewhere else and
# rename it into place: cp truncates before it writes, and a poll landing in that window
# would read a half-written file.
set_scenario() { cp "$1" "$here/.scenario.tmp" && mv "$here/.scenario.tmp" "$here/scenario.json"; }

# Whatever happens after the shell is restarted with the stub on PATH, the user needs to
# be told how to get their real shell back. Without this an abort mid-run (set -e) left
# them on the stub with no instructions printed.
restore_note() {
  cat <<'NOTE'

Restore the real headsetcontrol when finished:
  PID=$(pgrep -x qs || true); PID="${PID%%$'\n'*}"; [ -n "$PID" ] && kill -TERM "$PID"; sleep 2
  setsid nohup qs -c noctalia-shell > /tmp/noctalia.log 2>&1 < /dev/null & disown
NOTE
}
trap restore_note EXIT

echo "restarting noctalia-shell with the stub on PATH..."
set_scenario "$here/scenarios/1-full.json"
# `pgrep | head -1` is the pipefail trap this repo documents: pgrep exits 1 when nothing
# matches, head exiting early can make the pipeline report 141, and either way `set -e`
# kills the script at the assignment - before the shell is even restarted, with no output.
PID="$(pgrep -x qs || true)"; PID="${PID%%$'\n'*}"
[ -n "$PID" ] && kill -TERM "$PID"
sleep 2
env NOCTALIA_DEBUG=1 PATH="$here:$PATH" setsid nohup qs -c noctalia-shell > "$log" 2>&1 < /dev/null &
disown
sleep 7

for f in "$here"/scenarios/*.json; do
  name="$(basename "$f" .json)"
  # The device name identifies which scenario a state line came from. Waiting for the
  # line count alone was not enough: the plugin's own 60s poll can land between the swap
  # and the check, satisfying the wait with the PREVIOUS scenario's data, which then gets
  # printed under this scenario's heading as a plausible-looking pass.
  want="$(sed -n 's/.*"device"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | head -n 1 || true)"
  set_scenario "$f"
  before="$(state_count)"
  qs -c noctalia-shell ipc call plugin:headset-control refresh >/dev/null 2>&1 || true
  got=""
  for _ in $(seq 20); do
    if [ "$(state_count)" -gt "$before" ]; then
      line="$(last_state)"
      case "$line" in
        *"name='$want'"*) got="$line"; break ;;
      esac
    fi
    sleep 0.3
  done
  if [ -n "$got" ]; then
    printf '\n### %s\n%s\n' "$name" "$got"
  else
    # Never fall through printing the last line in the log: that is the previous
    # scenario's state, and it looks exactly like a pass.
    printf '\n### %s\nTIMEOUT - no state line for this scenario (expected name=%s)\n' "$name" "'$want'"
    fail=1
  fi
done

cat <<'NOTE'

Panel and bar checks have to be done by eye — open the panel while a scenario is loaded:
  qs -c noctalia-shell ipc call plugin openPanel headset-control
NOTE

[ "${fail:-0}" = 0 ] || { echo; echo "run.sh: at least one scenario produced no state line" >&2; exit 1; }

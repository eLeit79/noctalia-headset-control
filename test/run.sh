#!/usr/bin/env bash
#
# Cycle every capability scenario past the running plugin and print the state it derives.
#
# This RESTARTS noctalia-shell with the stub headsetcontrol on PATH and NOCTALIA_DEBUG=1
# (the state line is logged at debug level). Your real headset is not touched: the stub
# swallows every setter. The bar will show simulated devices until you restore the shell,
# which the script tells you how to do at the end.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log=/tmp/noctalia.log

state_count() { grep "HeadsetControl" "$log" 2>/dev/null | grep -c "state " || true; }

echo "restarting noctalia-shell with the stub on PATH..."
cp "$here/scenarios/1-full.json" "$here/scenario.json"
PID="$(pgrep -x qs | head -1)"; [ -n "$PID" ] && kill -TERM "$PID"
sleep 2
env NOCTALIA_DEBUG=1 PATH="$here:$PATH" setsid nohup qs -c noctalia-shell > "$log" 2>&1 < /dev/null &
disown
sleep 7

for f in "$here"/scenarios/*.json; do
  name="$(basename "$f" .json)"
  cp "$f" "$here/scenario.json"
  before="$(state_count)"
  qs -c noctalia-shell ipc call plugin:headset-control refresh >/dev/null 2>&1 || true
  for _ in $(seq 20); do
    [ "$(state_count)" -gt "$before" ] && break
    sleep 0.3
  done
  printf '\n### %s\n%s\n' "$name" \
    "$(grep "HeadsetControl" "$log" | grep "state " | tail -1 | sed 's/.*state //')"
done

cat <<'NOTE'

Panel and bar checks have to be done by eye — open the panel while a scenario is loaded:
  qs -c noctalia-shell ipc call plugin openPanel headset-control

Restore the real headsetcontrol when finished:
  PID=$(pgrep -x qs | head -1); [ -n "$PID" ] && kill -TERM "$PID"; sleep 2
  setsid nohup qs -c noctalia-shell > /tmp/noctalia.log 2>&1 < /dev/null & disown
NOTE

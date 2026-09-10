#!/usr/bin/env bash
#
# Wire this plugin into noctalia's plugin directory.
#
#   ./install.sh          symlink each packaged file into the plugin dir (dev default)
#   ./install.sh --copy   copy them instead, for a machine with no checkout
#
# Only the package directory (the one holding manifest.json, named after the plugin id)
# is installed. Everything beside it here — test/, install.sh, CLAUDE.md — is repo-only,
# and is exactly what noctalia would ship if it lived inside the package: installing a
# plugin copies that whole directory verbatim, minus settings.json.
#
# The plugin directory is always a real directory, never a symlink to the package:
# noctalia writes its runtime settings.json to <pluginsDir>/<id>/settings.json (hardcoded
# in PluginRegistry.getPluginSettingsFile), so a directory symlink would land that state
# back in the source tree.

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# `find ... | head -1` is a trap under `set -o pipefail`: once head has its line and
# exits, a still-walking find takes SIGPIPE, the pipeline reports 141, and `set -e`
# kills us with no message at all. `-print -quit` stops find itself, so there is no
# pipeline left to fail.
manifest="$(find "$repo" -mindepth 2 -maxdepth 2 -name manifest.json -not -path '*/.git/*' -print -quit)"
[ -n "$manifest" ] || { echo "install.sh: no <package>/manifest.json found under $repo" >&2; exit 1; }
pkg="$(dirname "$manifest")"

python="$(command -v python3 || true)"

# Read one string value out of a JSON file, taking the first match in document order
# wherever it is nested — registry.json keeps the version inside plugins[], not at the
# top level. The old `sed 's/.*"key"...\1/'` was greedy, so it returned the LAST match
# on a line; that is merely lucky on pretty-printed JSON and plainly wrong the moment
# the file is minified onto one line. python3 parses the thing properly when it is on
# the machine; the awk fallback keeps a python-less box working, and awk's match() is
# leftmost, so it agrees on which occurrence wins. Neither uses a pipe into head.
json_get() {
  local key="$1" file="$2" out=""
  if [ -n "$python" ]; then
    out="$("$python" -c '
import json, sys

def walk(node, key):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key and isinstance(v, str):
                return v
            found = walk(v, key)
            if found is not None:
                return found
    elif isinstance(node, list):
        for v in node:
            found = walk(v, key)
            if found is not None:
                return found
    return None

with open(sys.argv[1]) as fh:
    doc = json.load(fh)
value = walk(doc, sys.argv[2])
if value is not None:
    print(value)
' "$file" "$key" 2>/dev/null)" || out=""
  fi
  # No python3, or it choked on the file: fall back to a plain scan.
  if [ -z "$out" ]; then
    out="$(awk -v key="$key" '
      match($0, "\"" key "\"[ \t]*:[ \t]*\"[^\"]*\"") {
        s = substr($0, RSTART, RLENGTH)
        sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", s)
        sub(/"$/, "", s)
        print s
        exit
      }' "$file")" || out=""
  fi
  printf '%s' "$out"
}

id="$(json_get id "$manifest")"
[ -n "$id" ] || { echo "install.sh: no \"id\" in $manifest" >&2; exit 1; }
[ "$(basename "$pkg")" = "$id" ] || {
  echo "install.sh: package dir '$(basename "$pkg")' must be named after the manifest id '$id'," >&2
  echo "            because installing sparse-checks-out the directory named for the id." >&2
  exit 1
}

# registry.json advertises the version; the shell compares it against the installed
# manifest to offer updates, so a mismatch silently breaks update detection.
if [ -f "$repo/registry.json" ]; then
  mver="$(json_get version "$manifest")"
  rver="$(json_get version "$repo/registry.json")"
  [ "$mver" = "$rver" ] || echo "install.sh: WARNING version drift - manifest.json $mver vs registry.json $rver" >&2
fi

dest="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/plugins/$id"
mode="${1:-}"
case "$mode" in
  ""|--symlink) mode=symlink ;;
  --copy) mode=copy ;;
  *) echo "install.sh: unknown option '$mode' (expected --copy)" >&2; exit 1 ;;
esac

# An earlier install symlinked a whole directory; replace it with a real one.
if [ -L "$dest" ]; then
  echo "replacing directory symlink with a real directory: $dest"
  rm "$dest"
fi
mkdir -p "$dest"

# Rescue runtime state left in the source tree by such an install.
if [ -f "$pkg/settings.json" ]; then
  if [ -e "$dest/settings.json" ]; then
    echo "note: $dest/settings.json exists; leaving $pkg/settings.json alone" >&2
  else
    mv "$pkg/settings.json" "$dest/settings.json"
    echo "moved runtime settings.json out of the source tree"
  fi
fi

# Drop anything in the plugin dir that is no longer part of the package.
for f in "$dest"/* "$dest"/.[!.]*; do
  # -e alone is two tests in one: it skips a glob that matched nothing, but it also
  # skips a dangling symlink from an older layout — which is exactly the rubbish this
  # loop exists to clear. -L catches those; an unmatched glob is neither.
  [ -e "$f" ] || [ -L "$f" ] || continue
  name="$(basename "$f")"
  if [ "$name" = settings.json ]; then continue; fi
  if [ -e "$pkg/$name" ]; then continue; fi
  echo "removing stale $name"
  rm -rf "$f"
done

for f in "$pkg"/* "$pkg"/.[!.]*; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  if [ "$name" = settings.json ]; then continue; fi
  # Clear the destination entry first, whatever it happens to be. `ln -sfn` cannot
  # replace a real directory: it silently falls back to its "make the link inside the
  # directory" form and leaves $dest/i18n/i18n next to the stale copies from an earlier
  # --copy (or from a plugin installed through noctalia itself). The stale-entry loop
  # above never notices, because i18n does exist in the package. settings.json is
  # skipped just above, so this only ever removes something we are about to put back.
  rm -rf "$dest/$name"
  if [ "$mode" = copy ]; then
    cp -r "$f" "$dest/$name"
  else
    ln -s "$f" "$dest/$name"
  fi
done

echo "installed $id ($mode) from $(basename "$pkg")/ -> $dest"

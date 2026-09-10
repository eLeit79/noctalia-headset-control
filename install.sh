#!/usr/bin/env bash
#
# Wire this plugin into noctalia's plugin directory.
#
#   ./install.sh                symlink each packaged file into the plugin dir (dev default)
#   ./install.sh --copy         copy them instead, for a machine with no checkout
#   ./install.sh [--copy] <pkg> pick a package explicitly, when the repo holds several
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

mode=symlink
want=""
for arg in "$@"; do
  case "$arg" in
    --symlink) mode=symlink ;;
    --copy)    mode=copy ;;
    -*)        echo "install.sh: unknown option '$arg' (expected --copy or --symlink)" >&2; exit 1 ;;
    *)
      [ -z "$want" ] || { echo "install.sh: give at most one package name (got '$want' and '$arg')" >&2; exit 1; }
      want="${arg%/}"
      ;;
  esac
done

# The publishing model is one directory per plugin, so a repo may hold several. Taking
# whichever manifest the filesystem yielded first would install an arbitrary one and
# report success; be explicit instead.
# Reading find's output through a `while read` rather than `| head -1` keeps it clear of
# the pipefail trap: head exiting early makes a still-walking find take SIGPIPE, the
# pipeline report 141, and `set -e` kill us with no message at all.
manifests=()
while IFS= read -r line; do
  manifests+=("$line")
done < <(find "$repo" -mindepth 2 -maxdepth 2 -name manifest.json -not -path '*/.git/*' | sort)

if [ -n "$want" ]; then
  manifest="$repo/$want/manifest.json"
  [ -f "$manifest" ] || { echo "install.sh: no manifest.json in $repo/$want" >&2; exit 1; }
elif [ "${#manifests[@]}" -eq 1 ]; then
  manifest="${manifests[0]}"
elif [ "${#manifests[@]}" -eq 0 ]; then
  echo "install.sh: no <package>/manifest.json found under $repo" >&2
  exit 1
else
  echo "install.sh: this repo holds several packages; name the one to install:" >&2
  for m in "${manifests[@]}"; do echo "            $(basename "$(dirname "$m")")" >&2; done
  exit 1
fi
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
# manifest to offer updates, so a mismatch silently breaks update detection. The entry
# has to be matched on id: a repo with several packages has several versions in there,
# and the first one is not necessarily this package's.
if [ -f "$repo/registry.json" ]; then
  mver="$(json_get version "$manifest")"
  if [ -n "$python" ]; then
    "$python" -c '
import json, sys
reg, pid, mver = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    doc = json.load(open(reg))
except Exception as exc:
    print("install.sh: WARNING cannot parse registry.json (%s)" % exc)
    raise SystemExit(0)
entries = [e for e in (doc.get("plugins") or []) if isinstance(e, dict)]
match = [e for e in entries if e.get("id") == pid]
if not match:
    print("install.sh: WARNING registry.json lists no plugin with id \"%s\" - a remote "
          "install sparse-checks-out the directory named by the registry id, so it "
          "would fetch nothing" % pid)
    raise SystemExit(0)
rver = match[0].get("version")
if rver != mver:
    print("install.sh: WARNING version drift - manifest.json %s vs registry.json %s"
          % (mver, rver))
' "$repo/registry.json" "$id" "$mver" >&2 || true
  else
    # No python3: fall back to the first version in the file, which is only meaningful
    # for a single-package repo.
    rver="$(json_get version "$repo/registry.json")"
    [ "$mver" = "$rver" ] || echo "install.sh: WARNING version drift - manifest.json $mver vs registry.json $rver (approximate check: no python3)" >&2
  fi
fi

# Commons/Settings.qml reads NOCTALIA_CONFIG_DIR first and only then falls back to
# XDG_CONFIG_HOME/HOME. Installing to the wrong one of those puts the plugin somewhere
# the shell never scans, while still reporting success.
if [ -n "${NOCTALIA_CONFIG_DIR:-}" ]; then
  config="${NOCTALIA_CONFIG_DIR%/}"
elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
  config="${XDG_CONFIG_HOME%/}/noctalia"
elif [ -n "${HOME:-}" ]; then
  config="$HOME/.config/noctalia"
else
  echo "install.sh: none of NOCTALIA_CONFIG_DIR, XDG_CONFIG_HOME or HOME is set;" >&2
  echo "            nowhere to install to." >&2
  exit 1
fi
dest="$config/plugins/$id"

# Every destination entry is cleared before being rewritten, so an abort partway through
# leaves a plugin dir with some files missing - which noctalia will scan and fail to load.
# Nothing here can roll that back, but it should at least not fail silently.
trap 'echo "install.sh: FAILED partway through - $dest may be incomplete; re-run to finish it" >&2' ERR

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
for f in "$dest"/* "$dest"/.[!.]* "$dest"/..?*; do
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

for f in "$pkg"/* "$pkg"/.[!.]* "$pkg"/..?*; do
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

trap - ERR
echo "installed $id ($mode) from $(basename "$pkg")/ -> $dest"

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

manifest="$(find "$repo" -mindepth 2 -maxdepth 2 -name manifest.json -not -path '*/.git/*' | head -1)"
[ -n "$manifest" ] || { echo "install.sh: no <package>/manifest.json found under $repo" >&2; exit 1; }
pkg="$(dirname "$manifest")"

id="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1)"
[ -n "$id" ] || { echo "install.sh: no \"id\" in $manifest" >&2; exit 1; }
[ "$(basename "$pkg")" = "$id" ] || {
  echo "install.sh: package dir '$(basename "$pkg")' must be named after the manifest id '$id'," >&2
  echo "            because installing sparse-checks-out the directory named for the id." >&2
  exit 1
}

# registry.json advertises the version; the shell compares it against the installed
# manifest to offer updates, so a mismatch silently breaks update detection.
if [ -f "$repo/registry.json" ]; then
  mver="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1)"
  rver="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$repo/registry.json" | head -1)"
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
  [ -e "$f" ] || continue
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
  if [ "$mode" = copy ]; then
    rm -rf "$dest/$name"
    cp -r "$f" "$dest/$name"
  else
    ln -sfn "$f" "$dest/$name"
  fi
done

echo "installed $id ($mode) from $(basename "$pkg")/ -> $dest"

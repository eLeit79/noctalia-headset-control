#!/usr/bin/env bash
#
# Wire this plugin into noctalia's plugin directory.
#
#   ./install.sh          symlink each source file into the plugin dir (dev default)
#   ./install.sh --copy   copy them instead, for a machine with no checkout
#
# The plugin directory is always a real directory, never a symlink to this one:
# noctalia writes its runtime settings.json to <pluginsDir>/<id>/settings.json
# (hardcoded in PluginRegistry.getPluginSettingsFile), so a directory symlink
# would land that state back in the source tree.

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$src/manifest.json" | head -1)"
[ -n "$id" ] || { echo "install.sh: no \"id\" found in manifest.json" >&2; exit 1; }

dest="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/plugins/$id"
mode="${1:-}"
case "$mode" in
  ""|--symlink) mode=symlink ;;
  --copy) mode=copy ;;
  *) echo "install.sh: unknown option '$mode' (expected --copy)" >&2; exit 1 ;;
esac

# Repo-only files, plus the runtime state we are deliberately keeping out.
skip() {
  case "$1" in
    settings.json|install.sh|CLAUDE.md|.git|.gitignore) return 0 ;;
    *) return 1 ;;
  esac
}

# An earlier install symlinked the whole directory; replace it with a real one.
if [ -L "$dest" ]; then
  echo "replacing directory symlink with a real directory: $dest"
  rm "$dest"
fi
mkdir -p "$dest"

# Rescue runtime state that a directory-symlink install left in the source tree.
if [ -f "$src/settings.json" ]; then
  if [ -e "$dest/settings.json" ]; then
    echo "note: $dest/settings.json exists; leaving $src/settings.json alone" >&2
  else
    mv "$src/settings.json" "$dest/settings.json"
    echo "moved runtime settings.json out of the source tree"
  fi
fi

# Drop anything in the plugin dir that is no longer a source file.
for f in "$dest"/* "$dest"/.[!.]*; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  if [ "$name" = settings.json ]; then continue; fi
  if [ -e "$src/$name" ] && ! skip "$name"; then continue; fi
  echo "removing stale $name"
  rm -rf "$f"
done

for f in "$src"/* "$src"/.[!.]*; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  if skip "$name"; then continue; fi
  if [ "$mode" = copy ]; then
    rm -rf "$dest/$name"
    cp -r "$f" "$dest/$name"
  else
    ln -sfn "$f" "$dest/$name"
  fi
done

echo "installed $id ($mode) -> $dest"

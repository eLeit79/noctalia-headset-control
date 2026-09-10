# noctalia-headset-control

A noctalia-shell (Quickshell) plugin showing a USB gaming headset's battery in the niri
bar, with a panel for sidetone, auto power-off and voice prompts. It drives the headset
through `headsetcontrol` (official `extra` repo package, not the AUR).

This file is the project's context of record — architecture, measured constraints, the dev
loop and the reasoning behind past decisions. `README.md` is the user-facing half; prefer
putting anything a user would read there and linking rather than duplicating.

Built and tested against noctalia-shell 4.7.7-3, `headsetcontrol` 4.0.0, niri/Wayland on
CachyOS. Test hardware: **HyperX Cloud Alpha Wireless**, USB id `0x03f0:0x098d`, reporting
`CAP_SIDETONE`, `CAP_BATTERY_STATUS`, `CAP_INACTIVE_TIME`, `CAP_VOICE_PROMPTS`. No other
headset has ever been attached, but the capability gating is no longer unexercised: it was
tested on 2026-09-10 by putting a stub `headsetcontrol` on the shell's `PATH` and feeding
it scenarios for other devices, which found three real bugs (see below). That harness is
committed as `test/` — run `./test/run.sh` after touching anything capability-related.
`Main.qml` logs its derived state at debug level for it to read.

## Git workflow

`main` must always be in a working state, so it is never where development happens.

1. **Branch from `main` before writing anything**: `git switch -c <topic>`.
2. Work there. One branch can carry several changes — no need to merge after every small
   thing — but **each significant feature or bugfix gets its own commit**, so it can be
   read, reverted or cherry-picked on its own.
3. When the work is done *and verified*, merge back and push:

```sh
git switch main && git merge --no-ff <topic> && git push && git branch -d <topic>
```

`--no-ff` is deliberate: it records the branch boundary even for a single commit, so a
feature that later turns out to be wrong reverts as one unit. That recoverability is the
whole point of the rule.

Pushing merged `main` is part of this routine and needs no separate approval. Anything
else outward-facing — force-pushing, rewriting published history, creating remotes or
releases — still does.

## Layout

```
registry.json          the index a noctalia plugin source must expose (repo-only)
install.sh             wires the package into ~/.config/noctalia/plugins (repo-only)
CLAUDE.md              this file (repo-only)
test/                  stub headsetcontrol + capability scenarios (repo-only)
headset-control/       THE PACKAGE — only this is ever shipped to users
  manifest.json        plugin id, version, entryPoints, defaultSettings
  Main.qml             headless logic: polls battery, exposes state, applies settings, IPC
  BarWidget.qml        the bar capsule (icon + percentage); left-click opens the panel
  Panel.qml            the popup: sidetone / auto power-off / voice prompts
  Settings.qml         noctalia's per-widget settings page (poll interval, thresholds)
  i18n/en.json         user-visible strings
  README.md            user-facing docs
```

**The split is load-bearing, not tidiness.** Installing a plugin copies its directory
verbatim — see *Publishing* — so anything inside `headset-control/` ships to every user.
Development-only material must live beside it, never in it.

`entryPoints` in `manifest.json` maps roles to those filenames. The names are technically
free-form, but `Main`/`BarWidget`/`Panel`/`Settings` is the convention 98 of 99 official
plugins follow — keep it.

## Architecture

`Main.qml` is the single source of truth. It runs `headsetcontrol -b -o json` on a timer
(default 60 s) and publishes device state (`batteryLevel`, `batteryStatus`, `deviceName`,
`online`, `charging`, `capabilities`, `productId`), the derived `has*` capability flags,
the last-applied control values, and the `apply*()` / `refresh()` functions.
`BarWidget.qml` and `Panel.qml` are pure views over `pluginApi.mainInstance` — keep logic
out of them.

`headsetcontrol` can *set* sidetone, voice prompts and inactive time on this device but
cannot read them back, so the panel necessarily shows the last value applied from here. A
change made with the headset's own buttons will not be reflected.

**Settings persistence** is `pluginApi.pluginSettings.<key> = v` then
`pluginApi.saveSettings()` — see `persist()` in `Main.qml`.

## Strings and formatting

Every user-visible string goes through `root.tr("dot.separated.key")`, with the English
text in `i18n/en.json`; a missing key renders visibly as `!!key!!`. `Logger` messages stay
inline English — they are dev-facing, like noctalia's own.

Each view file defines its own small `tr()` wrapper that reads `trVersion`
(`pluginApi.translationVersion`). That read is deliberate: `pluginApi.tr()` is a plain
function, so without a property dependency a binding would never re-evaluate when the
language changes. The plugin API's own comment asks plugins to depend on it.

`pluginApi.tr(key, {name: value})` interpolates `{name}` placeholders; `trp(key, count)`
picks `key` vs `key-plural`. `trp` is unused here because every count in this UI comes off
a slider whose step never yields 1, so the singular forms would be dead keys.

Adding a language is just `headset-control/i18n/<langCode>.json` — then re-run
`install.sh`, since a new file needs its symlink. Missing keys fall back to English automatically.

The QML is formatted with **`qmlformat --indent-width 2 -i`** (the Qt6 binary at
`/usr/lib/qt6/bin/qmlformat`; the one on `PATH` is Qt5's). All four files are byte-clean
against it — keep them that way, and note the default 4-space width would reformat
everything.

## Constraints that were measured, not assumed

Do not "fix" these; reverting them re-introduces bugs.

**Sidetone on the Cloud Alpha Wireless (`0x098d`) is on/off only.** `headsetcontrol -s N`
sends an enable command (`0x21bb1001`) then a raw, unscaled level byte (`0x21bb11 <N>`).
The level byte has no audible effect — verified by sweeping 1, 2, 3, 4, 5, 6, 8, 10, 12,
16, 24, 32, 48, 64, 96 and 127 while talking — and `128` (`0x80`) is out of range and
silences sidetone entirely. The reference GUI for this headset agrees: it only ever sends
the on/off commands (`0x21bb1001` / `0x21bb1000`) and leaves its level-response handler
(`case 0x11`) an empty stub. So `0x098d` gets a **toggle** (enabling at level 64) and
every other device gets a 0-127 slider, on the assumption other hardware honours levels
until someone measures otherwise. **Do not "restore" a slider for `0x098d`** — it was
tried twice and looks broken both times, because the hardware has no such control.

**Panel controls are gated on the device's reported `capabilities`.** Never render a
control unconditionally. Capabilities are intentionally retained when the headset goes
offline, so the panel doesn't empty out while it sleeps.

**What resets the auto power-off timer is undocumented.** `headsetcontrol -i N`
(`0x21bb12 <minutes>`, 0 = never, clamped 0-90 here). The plugin's own 60-second battery
polling demonstrably does *not* keep the headset awake — it still powered off on schedule.
Host audio probably does, but that was never tested; don't state it as fact.

**What `headsetcontrol -b -o json` actually reports**, measured against the real device:

| State | `device_count` | per-device `status` | `battery` |
|---|---|---|---|
| Headset on | 1 | `success` | `BATTERY_AVAILABLE` + level |
| Headset off, dongle plugged | 1 | `partial` | `BATTERY_UNAVAILABLE`, level -1, plus `errors.battery` |
| Dongle unplugged | 0 | — | — (and exit code 1) |

**What is enumerated is the dongle, not the headset.** A wireless headset stays in the
device list while powered off, so "a device is listed" never means "the headset is awake".
Exit code is 1 when nothing is found; the plugin ignores the code and parses stdout, which
is valid JSON in every case above.

**A device that reports no battery is still a device.** Its identity and capabilities must
be read so the panel can offer what it does support; only the battery fields go
unavailable. Conflating "no battery object" with "no device" hid every control on such a
headset *and* left the previous device's name and capabilities on display. Equally,
`deviceFound` — not `capabilities.length` — is what distinguishes "nothing has reported
yet" from "this device reports nothing adjustable".

**A device with no battery capability shows the icon alone** in the bar, never a
percentage and never the crossed-out battery icon (which reads as "battery dead" rather
than "no battery to report"). Its visibility can only follow whether the device is
enumerated, so **sleep cannot be detected for such a device** — we have no signal for it.
Devices that do report battery are unaffected: availability of a reading is still what
hides the widget. Retaining capabilities while offline is what keeps an unplugged dongle
on the hidden path rather than the icon-only one.

**A battery reading that never moves is normal, not a stuck poll.** The Cloud Alpha
Wireless is rated ~300 h, so 1% is roughly 3 h of use and the value legitimately sits
still for a whole session. Polling was verified 2026-09-10 (two ticks exactly 60 s apart,
value matching a direct `headsetcontrol` read). If it ever does look wedged, the thing to
suspect is `refresh()`'s `if (poll.running) return;` guard latching on a process that
never finished — check `pgrep -a headsetcontrol` for a stray.

**Physical controls** — worth knowing when the user reports "the mic is dead":

- The mic boom LED is **inverted**: red = MUTED, unlit = live.
- The boom does **not** flip-to-mute on this model; the earcup button mutes.
- **Long-pressing** that same button toggles firmware sidetone.
- Hardware mute is upstream of PipeWire, so `wpctl` / `pactl` cheerfully report volume
  1.00 and `Mute: no` while recordings are completely silent.

## Publishing

There is no build step and no packaging format. A **plugin source is a git repo** that has:

1. `registry.json` at its root — `{"plugins": [{id, name, version, author, description,
   tags, official, minNoctaliaVersion, lastUpdated}]}`. This is the index the shell fetches
   (sparse checkout of that one file).
2. **one directory per plugin, named exactly the manifest `id`.**

Installing plugin `X` sparse-checks-out the `X/` directory and runs, in effect:

```sh
rm -f "$tmp/X/settings.json" && cp -r "$tmp/X/." "$pluginDir/"
```

So **the package is everything in that directory**, dotfiles included, with `settings.json`
as the single hard-coded exclusion. There is no `files` list and no ignore mechanism —
which is the whole reason `test/`, `install.sh` and this file sit *outside*
`headset-control/`.

Two ways to publish, both needing that layout:

- **Self-hosted**: anyone adds this repo's URL as a source in their `plugins.json`. That
  works today; `registry.json` is what makes it possible.
- **Upstream**: contribute the `headset-control/` directory plus a `registry.json` entry to
  `noctalia-dev/noctalia-plugins`.

`registry.json` and `manifest.json` both carry the version, and the update check compares
the registry's against the installed manifest's — so **bump both together** or update
detection silently breaks. `install.sh` warns on drift.

## Install wiring

`./install.sh` makes `~/.config/noctalia/plugins/headset-control` a **real directory
holding one symlink per packaged file** (`--copy` copies instead, for a machine with no
checkout). It installs only the package directory, and finds it by looking for the
`*/manifest.json` whose directory name matches the manifest `id`.

Don't symlink the whole project folder in. `PluginRegistry.getPluginSettingsFile()`
hardcodes runtime settings to `<pluginsDir>/<id>/settings.json` (`PluginRegistry.qml:577`),
so a directory symlink writes noctalia's live state straight into the source tree — which
is exactly what it used to do until 2026-09-10. With the per-file farm that state lands in
the plugin dir and the project stays clean; `.gitignore` still lists `settings.json` only
as a guard against reverting to a directory symlink.

Per-file symlinks are a supported arrangement, not a trick: noctalia's hot-reload watcher
globs the plugin dir with `find -L … -name '*.qml'` and its comment says this is *because*
plugins get symlinked in (`PluginService.qml:1844`). Re-run `install.sh` when you add,
rename or remove a file — plain edits need nothing.

Three things register the plugin. If it stops appearing, check all three:

1. Directory present at `~/.config/noctalia/plugins/headset-control`, with a
   `manifest.json` whose `id` matches the directory name.
2. `~/.config/noctalia/plugins.json` → `states["headset-control"] = {"enabled": true}`.
   Local plugins need no `sourceUrl`; without one the registry uses the plain id as key.
3. `~/.config/noctalia/settings.json` → an entry `{"id": "plugin:headset-control", ...}`
   in `bar.widgets.right`.

Config backups from the original install work: `~/.config/noctalia/*.bak-20260910-*`.

## Reloading after an edit

**Prefer hot reload — it works, and it works through the symlink farm.** Verified
2026-09-10: edit a file, and ~2-3 s later the plugin reloads in place (500 ms debounce),
bar widget unregistered and re-registered, `Panel.qml` edits included, repeat edits fine
because `reloadPlugin` rebuilds the watcher it tore down. Two conditions, both easy to
miss:

1. The shell must have been started with `NOCTALIA_DEBUG=1` in its environment —
   `Settings.isDebug` is `Quickshell.env("NOCTALIA_DEBUG") === "1"`
   (`Commons/Settings.qml:29`), read once at startup and not togglable at runtime.
2. Hot reload is then enabled **per plugin** with the bug icon on the plugin's row in
   Settings → Plugins → Installed (`ipc call settings openTab plugins`). That button is
   `visible: Settings.isDebug`, and `togglePluginHotReload` has no IPC binding — so the
   user has to click it. The enabled list is in memory only, so **it must be re-clicked
   after every shell restart**; turning debug mode off tears every watcher down too.

Debug mode raises log verbosity to DEBUG. It also tries to regenerate default-settings
files under the root-owned `/etc/xdg/quickshell/noctalia-shell/Assets/`, which fails
harmlessly — the user's own settings are untouched (checked).

Restarting the shell is the fallback, and the only way in when debug mode is off:

```sh
PID=$(pgrep -x qs | head -1); [ -n "$PID" ] && kill -TERM "$PID"
sleep 2
env NOCTALIA_DEBUG=1 setsid nohup qs -c noctalia-shell > /tmp/noctalia.log 2>&1 < /dev/null &
disown
```

**Never `pkill -f "qs -c noctalia-shell"`** — that pattern matches Claude Code's own Bash
command line and kills the agent's shell before the respawn runs, leaving the user with no
bar. Resolve the PID with `pgrep -x qs` and kill that, and keep the kill and respawn in one
command so a failure can't strand the user barless.

`Panel.qml` compiles lazily — hot reload picks up edits to it, but errors only surface when
the panel is opened:

```sh
qs -c noctalia-shell ipc call plugin openPanel headset-control
```

(That path centres the panel because there's no anchor widget — expected, not a bug.
`BarWidget.qml` passes `openPanel(root.screen, root)` and anchors correctly.)

Then check the log:

```sh
grep -iE "headset|plugin" /tmp/noctalia.log | head
grep -iE "error|TypeError|Cannot read|is not a function" /tmp/noctalia.log
```

Ignore these pre-existing unrelated warnings: xdg-portal registration, missing `Malicious`
colorscheme asset, GitHub API "Moved Permanently". A translation-watcher warning about
`i18n/en.json` is *not* in that list any more — the file exists now, so that warning means
the plugin dir is missing its `i18n` symlink (re-run `install.sh`).

## IPC

```sh
qs -c noctalia-shell ipc call plugin:headset-control refresh
qs -c noctalia-shell ipc call plugin:headset-control sidetone 64
qs -c noctalia-shell ipc call plugin:headset-control voicePrompts 1
qs -c noctalia-shell ipc call plugin:headset-control inactiveTime 30
```

Note the two different targets: plugin-declared handlers are `plugin:headset-control`,
while noctalia's own plugin management is `plugin` (e.g. `ipc call plugin openPanel
headset-control`).

## Reference material

- Plugin API source: `/etc/xdg/quickshell/noctalia-shell/Services/Noctalia/PluginService.qml`
  and `PluginRegistry.qml` (manifest validation, folder scan, composite keys, hot reload).
- Shell IPC surface: `/etc/xdg/quickshell/noctalia-shell/Services/Control/IPCService.qml`.
- Widgets: `/etc/xdg/quickshell/noctalia-shell/Widgets/` — `NToggle`, `NSlider` (a
  `Slider`, so `onPressedChanged` gives commit-on-release), `NLabel`, `NText`, `NDivider`.
- Icon names: `/etc/xdg/quickshell/noctalia-shell/Commons/IconsTabler.qml`
  (`bt-device-headset`, `battery-charging`, `battery-off`, …).
- Official plugins to copy patterns from: https://github.com/noctalia-dev/noctalia-plugins
  — `update-count` for a bar widget, `battery-threshold` for a panel.
- HeadsetControl source: https://github.com/Sapd/HeadsetControl, device implementation in
  `lib/devices/hyperx_cloud_alpha_wireless.hpp`.

## Not yet done

Nothing outstanding. If the plugin is to go upstream, that submission is the remaining
step: copy `headset-control/` into `noctalia-dev/noctalia-plugins` along with a
`registry.json` entry. Everything it required — i18n, a preview, a publishable layout — is
in place.

## Screenshots

`headset-control/preview.png` is repo-facing only — **the shell never renders it**; it is
shown by the package README and by the upstream plugin listing. So keep it at native
resolution rather than upscaling.

`grim` and `slurp` are **not installed** on this machine. Captures come from niri instead:

```sh
niri msg action screenshot-screen   # whole focused screen -> ~/Pictures/Screenshots/
```

Then crop with PIL. Two things that matter when reshooting: the panel only anchors above
the widget when it is opened by a real left-click (the `openPanel` IPC passes no anchor and
centres it), and the panel closes on a click elsewhere but *not* on mere pointer movement —
so click the widget, then move the pointer off it before capturing, or the cursor lands on
the battery percentage.

## Why it's built this way

The user's headset mic appeared dead; it turned out to be the inverted-LED hardware mute.
While debugging, a long-press enabled firmware sidetone, which raised the question of how
to control these settings without a terminal.

The first candidate was the AUR package `hyperx-alpha-wireless-git` (audited, clean: plain
cmake build, MIT, no install hooks). Its tray icon uses wxWidgets' `wxTaskBarIcon`, which
on GTK3 is **GtkStatusIcon** — the legacy XEmbed protocol. Noctalia is a
**StatusNotifierItem** host and nothing bridges the two, so that icon can never appear
without an XEmbed→SNI proxy (`xembedsniproxy`, a 0-vote AUR package) plus
`GDK_BACKEND=x11`. The whole chain was abandoned in favour of `headsetcontrol` (official
repo, scriptable) feeding this native plugin. For reference: `snixembed` is **not** the
package for that job — it proxies the opposite direction.

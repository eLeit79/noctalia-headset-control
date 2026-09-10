# Traps that have already been walked into

Each of these cost time once already. They are host and toolchain behaviour, not project
policy — the rest of the context of record is in [CLAUDE.md](CLAUDE.md), and the
constraints measured against the real hardware are in its *Constraints that were measured,
not assumed* section.

**Never colour text with `Color.mOnPrimary` unless it sits on a primary-coloured fill.**
`mOnPrimary` and `mSurface` are defined as the *same value* in the light variants of Ayu,
Catppuccin, Gruvbox, Kanagawa, Nord and Tokyo-Night (and in six dark variants), so text
using it on a surface is invisible. The settings page did this and nobody saw it because
this machine runs a dark scheme. `update-count` still has the bug — do not copy from it.

**`ln -sfn` does not replace a real directory.** It silently switches to its "create the
link inside the directory" form, so re-linking over a previously copied `i18n/` yields
`i18n/i18n` and keeps serving the stale translations. `install.sh` clears each destination
first; keep it that way.

**`cmd | head -1` is a hazard under `set -o pipefail`** — the left side takes SIGPIPE, the
pipeline returns 141, and `set -e` aborts with no message. Use `find -print -quit` or read
the whole value and trim.

**Quickshell's `Process` says nothing at all when a command cannot start.** No `exited`,
no `stdout.onStreamFinished` — `running` just goes back to false. Anything built on those
two signals is therefore blind to a missing binary, which is how "headsetcontrol is not
installed" used to render as "Waiting for headsetcontrol to report the device…" forever
while setters persisted values that reached nothing. `running` still reads true
synchronously after the assignment even for a command that cannot start, so this cannot be
detected inline; `startCheck` in `Main.qml` defers the check instead. `test/runtime.sh`
covers it.

**Killing an in-flight process reports a failure that is not one.** `run()` stops a
running command before starting its replacement, and the killed one exits 15 (SIGTERM),
which looked exactly like "the value was rejected" and reverted the value the replacement
was busy applying. Hence the `superseded` flag. A `running = false` is only a request, too:
a process ignoring SIGTERM needs `signal(9)`, which the poll watchdog escalates to.

**`closePanel(undefined)` does not do nothing.** `PanelService.getPanel(name, null)` falls
back to the first registered panel of that name on any screen (`:161-171`). A plugin's
`Settings.qml` is handed only `pluginApi` by `NPluginSettingsPopup` — never a `screen` —
so `closePanel(root.screen)` there closes an unrelated panel. `update-count` still does
this; along with `mOnPrimary`, that is the second thing not to copy from it.

**The external command is not to be trusted.** Every `headsetcontrol` call checks what
happened: the poll has a 15 s watchdog (its `if (poll.running) return` guard would
otherwise latch forever on a hung process and silently kill all polling), setters check
their exit code and revert the persisted value when the command fails, the IPC entry
points reject non-numeric input before it reaches `settings.json` or the command line, and
a poll with empty stdout marks the tool missing rather than looking like a missing headset.
A working `headsetcontrol` always prints JSON — it exits non-zero with no device attached,
so the exit code alone proves nothing. `./test/runtime.sh` exercises all of this against a
stub that fails on demand, and is confirmed to fail against the code from before these
were fixed.

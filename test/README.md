# Tests

Two harnesses, with different costs:

| | What it covers | Cost |
|---|---|---|
| `./test/runtime.sh` | What the plugin does when `headsetcontrol` misbehaves | Safe: nothing installed, no shell restarted, ~50s |
| `./test/run.sh` | Capability gating through the real UI | **Restarts your shell** with a stub on `PATH` |

Run `runtime.sh` after touching `Main.qml`, and `run.sh` after touching anything
capability-related.

## Runtime failure tests

    ./test/runtime.sh

Loads `Main.qml` on its own under `qs -p` with a stub `headsetcontrol`, and asserts the
state it ends in. It needs a running Wayland session (that is all `qs -p` needs), but it
installs nothing, kills nothing and never touches the headset.

These paths exist because each of them looks like a perfectly healthy plugin from the
outside:

| Case | The failure it guards against |
|---|---|
| healthy poll | Baseline: a real device parses |
| missing binary | Quickshell emits *neither* `exited` nor `streamFinished` when a command cannot start, so a missing `headsetcontrol` used to read as "no headset yet" forever, and setters persisted values that reached nothing |
| empty stdout | A tool that is present but prints nothing is missing or broken, not a missing headset |
| setter exits 3 | A rejected setting must be put back, not left on display |
| double apply | Killing an in-flight command must not revert the value its replacement is applying |
| hung poll recovers | A poll that hangs and ignores SIGTERM must not latch polling off until the shell restarts |

Confirmed to discriminate: run against the code from before these were fixed, four of the
six fail.

## Capability tests

The plugin gates every control on the capabilities `headsetcontrol` reports for the
connected device. Only one headset has ever been attached to it, so that gating is
exercised here with a **stub `headsetcontrol`** that reports devices we do not have.

It is worth running: on first use it found three real bugs — a headset reporting no
battery object was discarded as "no device", a device reporting zero capabilities was told
the plugin was still waiting for it, and a battery-less device was given the crossed-out
battery icon.

### Running

    ./test/run.sh

This restarts noctalia-shell with `test/` first on `PATH` and `NOCTALIA_DEBUG=1`, then
steps through every scenario and prints the state the plugin derives from it. The debug
flag matters: the state line is logged at debug level, so it is invisible in normal use.

Your real headset is never touched — the stub swallows every setter. The bar will show
simulated devices until you restore the shell; the script prints how, on the way out even
if it aborts partway. A scenario that produces no state line is reported as `TIMEOUT` and
fails the run, rather than being printed with the previous scenario's state.

Panel and bar appearance still has to be checked by eye; the script only proves the state
layer. Open the panel with a scenario loaded:

    qs -c noctalia-shell ipc call plugin openPanel headset-control

### Scenarios

| File | What it simulates | Expected |
|---|---|---|
| `1-full` | The real HyperX Cloud Alpha Wireless | Baseline; everything on, sidetone as a **toggle** |
| `2-battery-only` | Battery, nothing adjustable | Percentage shown, panel says nothing is adjustable |
| `3-sidetone-no-battery-key` | Sidetone, **no `battery` key at all** | Sidetone control offered; icon alone in the bar |
| `4-sidetone-battery-unavailable` | Sidetone, battery present but unavailable | Same as above |
| `5-other-vendor-sidetone` | Sidetone on a non-`0x098d` device | Sidetone as a **0-127 slider**, not a toggle |
| `6-no-sidetone` | Everything except sidetone | No sidetone control at all |
| `7-no-caps` | Device reporting zero capabilities | "This headset reports no adjustable settings." |
| `8-offline` | `device_count: 0` | Widget hidden, capabilities retained |
| `9-present-but-failed-read` | Enumerated but unreadable — the measured shape of a **sleeping** headset: `status: partial`, `BATTERY_UNAVAILABLE`, plus `errors.battery` | Widget hidden, panel keeps its controls |

Scenarios 3 and 4 are the interesting pair: a device can report no battery either by
omitting the key or by reporting it unavailable, and both must yield the same behaviour.

### Adding a scenario

Drop a JSON file in `scenarios/` shaped like real `headsetcontrol -b -o json` output. The
device name is what `run.sh` matches a state line against, so give each scenario its own.
`HEADSET_TEST_SCENARIO=/path/to.json` overrides which file the stub serves, for trying one
by hand without disturbing `scenario.json`. The
shapes the real tool actually produces are recorded in `../CLAUDE.md`; the short version is
that the **dongle** is what gets enumerated, so a device stays listed with
`"status": "partial"` while the headset is powered off, and only reaches `device_count: 0`
once the dongle is unplugged.

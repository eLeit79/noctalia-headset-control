# Capability tests

The plugin gates every control on the capabilities `headsetcontrol` reports for the
connected device. Only one headset has ever been attached to it, so that gating is
exercised here with a **stub `headsetcontrol`** that reports devices we do not have.

It is worth running: on first use it found three real bugs — a headset reporting no
battery object was discarded as "no device", a device reporting zero capabilities was told
the plugin was still waiting for it, and a battery-less device was given the crossed-out
battery icon.

## Running

    ./test/run.sh

This restarts noctalia-shell with `test/` first on `PATH` and `NOCTALIA_DEBUG=1`, then
steps through every scenario and prints the state the plugin derives from it. The debug
flag matters: the state line is logged at debug level, so it is invisible in normal use.

Your real headset is never touched — the stub swallows every setter. The bar will show
simulated devices until you restore the shell, which the script prints instructions for.

Panel and bar appearance still has to be checked by eye; the script only proves the state
layer. Open the panel with a scenario loaded:

    qs -c noctalia-shell ipc call plugin openPanel headset-control

## Scenarios

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
| `9-present-but-failed-read` | Enumerated but unreadable (asleep) | Widget hidden, panel keeps its controls |

Scenarios 3 and 4 are the interesting pair: a device can report no battery either by
omitting the key or by reporting it unavailable, and both must yield the same behaviour.

## Adding a scenario

Drop a JSON file in `scenarios/` shaped like real `headsetcontrol -b -o json` output. The
shapes the real tool actually produces are recorded in `../CLAUDE.md`; the short version is
that the **dongle** is what gets enumerated, so a device stays listed with
`"status": "partial"` while the headset is powered off, and only reaches `device_count: 0`
once the dongle is unplugged.

# Headset Control (noctalia plugin)

Shows a USB gaming headset's battery level in the noctalia bar, using
[`headsetcontrol`](https://github.com/Sapd/HeadsetControl).

Written for a HyperX Cloud Alpha Wireless (`0x03f0:0x098d`), but works with any
headset `headsetcontrol` reports a `battery` capability for.

## Requirements

- `headsetcontrol` (Arch: `pacman -S headsetcontrol`, official `extra` repo)
- noctalia-shell 4.x

## Behaviour

- Polls `headsetcontrol -b -o json` on a timer (default 60s).
- Shows a headset icon plus the battery percentage.
- Turns the label red at or below the low-battery threshold (default 20%).
- Shows a charging icon while charging.
- Hides itself while the headset is off or disconnected (configurable).
- Left-click opens a panel with mic monitoring (sidetone), auto power-off and
  voice prompt controls; right-click offers refresh and widget settings.

`headsetcontrol` can set sidetone, voice prompts and inactive time on this device
but cannot read them back, so the panel shows the last value applied from here.
Changing sidetone with the headset's own button (long-press) is therefore not
reflected in the panel.

## Other headsets

Nothing is hardcoded to one device. The plugin parses `headsetcontrol`'s JSON, so
the battery readout works for any supported headset that reports one, and each
control is shown only if the connected device reports the matching capability:

| Control | Requires |
|---|---|
| Battery readout | `CAP_BATTERY_STATUS` |
| Hear yourself (sidetone) | `CAP_SIDETONE` |
| Auto power-off | `CAP_INACTIVE_TIME` |
| Voice prompts | `CAP_VOICE_PROMPTS` |

If the device reports none of the three controls, the panel says so instead of
showing dead widgets. Capabilities are remembered from the last successful read,
so the panel does not empty out while the headset is asleep.

### Sidetone is on/off, not a level

The Cloud Alpha Wireless ignores the level byte `headsetcontrol` sends after the
sidetone enable command. Verified by sweeping levels 1, 2, 3, 4, 5, 6, 8, 10, 12,
16, 24, 32, 48, 64, 96 and 127 while talking: every non-zero level sounds
identical, and `128` (`0x80`) is out of range and silences it. The reference GUI for this headset
only ever sends the on/off commands (`0x21bb1001` / `0x21bb1000`) and leaves its
level-response handler an empty stub, which matches that behaviour. The panel
therefore exposes sidetone as a toggle for this product id (`0x098d`), enabling it
at level 64. Any other device gets a 0-127 level slider, on the assumption that it
honours levels until someone measures otherwise.

To experiment with raw levels anyway:

    qs -c noctalia-shell ipc call plugin:headset-control sidetone 40

Refresh can also be triggered externally:

    qs -c noctalia-shell ipc call plugin:headset-control refresh

## Install

Run the installer, then enable the plugin in `~/.config/noctalia/plugins.json`
and add `plugin:headset-control` to a bar section in
`~/.config/noctalia/settings.json`.

    ./install.sh            # symlink each file into the plugin dir (keeps edits live)
    ./install.sh --copy     # copy instead, for a machine with no checkout

Either way the plugin directory itself is a real directory, so the runtime
`settings.json` noctalia writes there stays out of this source tree. The
directory name under `plugins/` must match the manifest `id`.

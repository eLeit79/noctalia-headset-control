# noctalia-headset-control

A [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell) plugin that shows a USB
gaming headset's battery in the bar, with a panel for sidetone, auto power-off and voice
prompts. It drives the headset through
[`headsetcontrol`](https://github.com/Sapd/HeadsetControl).

![The panel open above the bar widget](headset-control/preview.png)

Nothing is hardcoded to one headset: the plugin parses `headsetcontrol`'s JSON and shows
each control only if the connected device reports the matching capability. Developed
against a HyperX Cloud Alpha Wireless.

**[Full plugin documentation →](headset-control/README.md)** — requirements, behaviour,
per-device capability gating, translations and IPC.

## Install

This repository is itself a noctalia **plugin source**, so it can be installed without a
checkout. Add it to `~/.config/noctalia/plugins.json`:

```json
{
  "sources": [
    {
      "enabled": true,
      "name": "Headset Control",
      "url": "https://github.com/eLeit79/noctalia-headset-control"
    }
  ]
}
```

Then install "Headset Control" from Settings → Plugins and add it to a bar section.

From a checkout instead:

```sh
./install.sh            # symlink the packaged files into the plugin dir
./install.sh --copy     # copy instead, for a machine with no checkout
```

`headsetcontrol` must be installed and able to reach the device as your own user — on Arch
that is `pacman -S headsetcontrol` from the official `extra` repo, which ships the udev
rules. See the [plugin README](headset-control/README.md#requirements) for the details.

## Layout

Only `headset-control/` is ever shipped to users — installing a plugin copies its
directory verbatim, so development-only material has to live beside it, never inside it.

```
headset-control/   the plugin package (manifest, QML, i18n, user README, preview)
registry.json      the index that makes this repo an installable plugin source
install.sh         wires the package into ~/.config/noctalia/plugins
test/              stub headsetcontrol + capability scenarios for other devices
CLAUDE.md          architecture, measured device behaviour, dev loop
```

## Contributing

`CLAUDE.md` is the context of record: architecture, the constraints that were measured
rather than assumed, and the traps already walked into. Read it before changing behaviour —
several things that look wrong are deliberate and documented there.

Two things to keep green:

```sh
./test/run.sh                                   # capability gating, 9 scenarios
/usr/lib/qt6/bin/qmlformat --indent-width 2 -i  # the Qt6 binary, not the one on PATH
```

Development happens on a branch off `main`, and `registry.json` and
`headset-control/manifest.json` carry the version in two places — bump both together or
noctalia's update check silently stops working.

## License

MIT — see [LICENSE](LICENSE).

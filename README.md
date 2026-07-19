# DankDisplayControl

A DankMaterialShell bar widget for controller-first or couch-oriented Hyprland
sessions. The bar pill shows the selected display policy, effective output
count, and mirror state. Its popout provides direct layout, mirror, and audio
controls.

## Features

- Shows both the selected layout policy and the outputs Hyprland is actually
  presenting
- Distinguishes active mirroring from mirroring that is armed until a second TV
  becomes available
- Labels large displays as primary/secondary TVs and smaller displays as the
  auxiliary display without persisting hardware identifiers
- Switches between adaptive, all-output, TV-pair, TV-plus-auxiliary, and
  single-output layouts
- Toggles display mirroring and optionally cycles the couch audio output
- Refreshes automatically after hotplug and display power changes

## Requirements

- DankMaterialShell 1.4 or newer
- Hyprland and `hyprctl`
- The following command contract:
  - `couch-display-layout status`
  - `couch-display-layout <layout>`
  - `couch-display-mirror status|toggle`
  - `couch-audio-output status|cycle`

The commands are intentionally separate from the plugin. The plugin owns the
presentation and interaction layer; the host configuration remains the source
of truth for policy, connector selection, workspaces, and audio routing.

## Installation

Copy or symlink this directory to
`~/.config/DankMaterialShell/plugins/DankDisplayControl`, enable
`dankDisplayControl`, and add it to a DMS bar configuration.

For a Nix installation, use the repository as a `flake = false` input and pass
it to the DMS plugin module as the plugin source.

## Development

Run the plugin checks with:

```bash
bash test.sh
```

Reload a development checkout with:

```bash
dms ipc call plugins reload dankDisplayControl
```

## License

MIT

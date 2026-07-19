# Contributing to DankDisplayControl

## Development setup

DankMaterialShell 1.4 or newer and the couch display command contract described
in the README are required for live testing.

Symlink a checkout into the DMS plugin directory:

```bash
ln -s "$(pwd)" ~/.config/DankMaterialShell/plugins/DankDisplayControl
dms ipc call plugins reload dankDisplayControl
```

Run the static plugin checks before committing:

```bash
bash test.sh
```

## Branches and releases

Develop changes on `dev` and open pull requests against `dev`. Releases are
made from `main`; the version in `plugin.json` is the release tag source of
truth.

Use `feat:`, `fix:`, `docs:`, `refactor:`, or `chore:` prefixes to keep history
scannable.

## License

Contributions are licensed under the MIT License.

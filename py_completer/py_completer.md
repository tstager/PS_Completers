# `py` completer

This completer provides a standalone native PowerShell argument completer for `py` / `py.exe`, covering both the Python install manager (`pymanager`, the `py` that ships with Python 3.14+ on Windows) and the legacy Python Launcher for Windows (PEP 397).

## Flavor detection

The first completion classifies the installed `py` once per session, without running it when possible: a `pymanager.exe` next to the resolved `py.exe` (or a `PythonManager` path segment) means `manager`; otherwise a bounded `py -h` is inspected for the "Python Launcher for Windows" banner, which means `legacy`.

## Covered surface (manager flavor)

- Commands: `exec`, `help`, `install`, `list`, `uninstall`
- Launch forms before a command: `-V:<TAG>`, `-V:COMPANY\TAG`, `-3<VERSION>` (`-3.14-64`, `-3.14.6-64`, ...)
- Global options after a command: `-v`/`--verbose`, `-vv`, `-q`/`--quiet`, `-qq`, `-y`/`--yes`, `-h`/`-?`/`--help`, `--config=<PATH>`
- `install`: `-s`/`--source=`, `-t`/`--target=` (directories), `-d`/`--download=` (directories), `-f`/`--force`, `-u`/`--update`, `--dry-run`, `--refresh`, `--configure`, `--by-id`, then installed tags, `Company\Tag` selectors and version hints
- `list`: `-f`/`--format=` (the 12 formats `py list -f formats` reports), `-1`/`--one`, `--online`, `-s`/`--source=`, `--only-managed`, then tags as `<FILTER>`
- `uninstall`: `--purge`, `--by-id`, then installed tags
- `help`: the five command names
- First positional script/file operand: filesystem path completion

## Covered surface (legacy flavor)

- Launcher flags: `-2`, `-3`, `-0`, `--list`, `-0p`, `--list-paths`, `-h`, `-?`, `--help`
- Selector forms `-V:TAG`, `-V:COMPANY\TAG`, `-3.14`, `-3.14-64` (`-32`/`-64` exist only as selector suffixes, never as standalone flags)

## Behavior notes

- Options are matched case-sensitively, so `py -v` (verbose) is never rewritten into `-V:`.
- Before a command, `-v`, `-y`, `--config=` and similar tokens are passed through to python by the manager (its global options must follow the command), so the completer offers a `<python-option>` placeholder there instead of pretending they are launcher options.
- Attached `--option=value` forms (`-f=json`, `--target=.\runtime`, `--config=settings.json`) are split and completed with the prefix preserved; the separate form (`py list -f <Tab>`) works as well.
- It reconstructs command text from `CommandAst.Extent.Text` plus `cursorPosition`, so trailing-space and attached-token handling follow the real native completion path.
- Runtime tags come from `py list -f=json` (`company`, `tag`, `install-for`, `run-for`) on the manager, and from `py -0p` on the legacy launcher, where the display notation `3.14[-64]` is expanded to `3.14` and `3.14-64`; both probes run with stdin closed under a 5 s timeout and are cached for 300 s.
- `-V:prefix` and `-V:COMPANY\` (or `COMPANY/`) remain in selector mode and use placeholders when no installed-tag match is available, rather than falling back to filesystem completion.
- Only one runtime selector is accepted, so after `-V:<TAG>` or `-3<VERSION>` the completer offers the script path slot and a `<python-option>` placeholder instead of re-offering the launcher table.
- After the first script/file operand is present, launcher switch completion stops. Subsequent completion is limited to path-like arguments or placeholder sentinels.

## Import-safe top-level shape

The script keeps its top level import-safe for `Import-CompleterScript` usage:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

All runtime discovery and caching happens lazily inside helper functions.

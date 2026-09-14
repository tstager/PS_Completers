# rtk PowerShell completer

This standalone completer registers native PowerShell completion for `rtk` and `rtk.exe`.

It uses local `rtk --help` and `rtk <subcommand> --help` output as the authoritative command surface, parses that help lazily at completion time, and caches parsed nodes for the rest of the session.

Implemented behavior:

- Root subcommand completion from local help.
- Per-command option completion from local help.
- Nested subcommand completion for command groups such as `telemetry` and `hook`.
- Value completion for documented `Possible values` blocks such as `rtk init --agent`.
- File/path completion for path-like arguments such as `rtk json <FILE>`, `rtk read <FILES>...`, and `rtk wget --output-document <OUTPUT>`.
- Placeholder completion for free-form argument slots such as `rtk err <COMMAND>...`; passthrough `[ARGS]...` slots fall back to file completion.
- Attached `--option=value` completion (for example `rtk read --level=min`).
- Enumerated values parsed from option descriptions (`rtk gain --tier`, `rtk gain --format`, `rtk git stash <SUBCOMMAND>`).
- A static fallback tree (root commands, `read`, `git`, `telemetry`, `hook`, `config`, `json`) that is only used when `rtk` is not on `PATH` or help capture fails; help capture closes stdin and is bounded at 5 s.

Top-level script shape stays `Import-CompleterScript`-safe: `Set-StrictMode`, function definitions, and one literal `Register-ArgumentCompleter -Native` call.

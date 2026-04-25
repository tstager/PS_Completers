# rtk PowerShell completer

This standalone completer registers native PowerShell completion for `rtk` and `rtk.exe`.

It uses local `rtk --help` and `rtk <subcommand> --help` output as the authoritative command surface, parses that help lazily at completion time, and caches parsed nodes for the rest of the session.

Implemented behavior:

- Root subcommand completion from local help.
- Per-command option completion from local help.
- Nested subcommand completion for command groups such as `telemetry` and `hook`.
- Value completion for documented `Possible values` blocks such as `rtk init --agent`.
- File/path completion for path-like arguments such as `rtk json <FILE>`, `rtk read <FILES>...`, and `rtk wget --output-document <OUTPUT>`.
- Placeholder completion for free-form passthrough argument slots where `rtk` intentionally forwards arguments to another tool.

Top-level script shape stays `Import-CompleterScript`-safe: `Set-StrictMode`, function definitions, and one literal `Register-ArgumentCompleter -Native` call.

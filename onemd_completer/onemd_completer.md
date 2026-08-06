# onemd completer

`onemd_completer.ps1` registers a standalone native PowerShell argument completer for the `onemd` CLI.

It uses `Register-ArgumentCompleter -Native` and loads the installed `onemd` CLI help lazily. The completer parses the root help from `onemd --help` and subcommand help from `onemd help <subcommand>` so it can offer:

- root-level subcommands such as `login`, `logout`, `whoami`, `notebooks`, `sections`, `import`, `update`, `export`, `sync`, `status`, and `help`;
- subcommand-specific options and inherited global options;
- value completions for explicit enum-style values when the help exposes them;
- path-aware completion for file and folder slots such as `<file.md>`, `<folder>`, `--output <file>`, `--report <path>`, and `--attachments-dir <path>`.

The completer is intentionally help-driven so it stays aligned with the installed `onemd` version instead of relying on a stale hand-maintained list.

Example usage:

```powershell
. .\onemd_completer.ps1
onemd <TAB>
onemd import <TAB>
onemd sync <TAB>
onemd import --report .\
```

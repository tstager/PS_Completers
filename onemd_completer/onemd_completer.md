# onemd completer

`onemd_completer.ps1` registers a standalone native PowerShell argument completer for the `onemd` CLI.

It uses `Register-ArgumentCompleter -Native` and loads the installed `onemd` CLI help lazily. The completer parses the root help from `onemd --help` and subcommand help from `onemd help <subcommand>` so it can offer:

- root-level subcommands such as `login`, `logout`, `whoami`, `notebooks`, `sections`, `import`, `update`, `export`, `sync`, `status`, `ui`, and `help` (`onemd help <TAB>` lists them once);
- subcommand-specific options and inherited global options, including the negated `--no-*` forms that only appear in usage lines and descriptions (`--no-render`, `--no-wiki-links`, `--no-color`, ...), in both the separate (`--fidelity full`) and attached (`--fidelity=full`) forms;
- value completions for `(a|b|c)` enums and for values stated in prose: word lists after a colon (`--tenant` -> `common`, `organizations`, `consumers`), small numeric ranges, defaults, minimums and ceilings (`--concurrency` -> `1`..`5`, `--max-depth` -> `5`, `10`), and the literal `-` for `-o/--output` and `export <page-id>`; other values fall back to the metavariable (`<seconds>`, `<id|name>`) instead of a generic placeholder;
- path-aware completion driven by the metavariable in the help row: `<folder>` is directory-only, `<file>` and `<path>` accept files and directories, and `<file.md>` operands are filtered to `.md` files plus directories to descend into.

Only the `Options:`/`Global options:` rows themselves are parsed; the prose blocks that follow them in `onemd help sync` are not mistaken for options. Tokens to the right of the cursor are ignored, and the word under the cursor is taken from the AST, so a partially typed value or operand (`onemd import REA<TAB>`) completes normally. After a subcommand, operand candidates are listed first and the option names after them.

The completer is intentionally help-driven so it stays aligned with the installed `onemd` version instead of relying on a stale hand-maintained list.

Example usage:

```powershell
. .\onemd_completer.ps1
onemd <TAB>
onemd import <TAB>
onemd sync <TAB>
onemd import --report .\
```

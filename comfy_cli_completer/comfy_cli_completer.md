# comfy-cli completer

This standalone PowerShell completer reads the installed CLI's machine-readable help, `comfy-cli.exe --help-json`. That single call returns the whole command tree. The completer runs it on the first Tab and caches the tree for the session, so later completions at any depth spawn nothing. The installed binary used during implementation was `C:\Users\Trent\AppData\Local\Programs\Python\Python314\Scripts\comfy-cli.exe` version 1.22.0.

The script registers the bare and `.exe` command names:

```powershell
Register-ArgumentCompleter -Native -CommandName @('comfy-cli', 'comfy-cli.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ComfyCli -Word $wordToComplete -Ast $commandAst -Cursor $cursorPosition
}
```

## What it completes

- **Commands and options.** It offers every visible command at every depth, plus each command's options with their aliases and `--no-` forms. Required options are included and their tooltips start with `Required.`. Hidden commands and options are not offered, but deprecated aliases such as `models` and `cs` are still recognised when typed. Short flags are case-sensitive, and every command offers `--help`.
- **Values with a fixed set of choices**, both as a separate argument and in `--name=value` form:
  - choice types such as `install --cuda-version` and `standalone --platform`;
  - boolean arguments (`true`, `false`);
  - lists written in the help text, such as `[remote|local|cache]`, `create_time | update_time | name`, `'httpx' (default) or 'aria2'`, `'full' (default) ...; 'summary' ...`, `one of: list, schema, ...` and a closed trailing list such as `Output kind: image, video, audio, 3d.`;
  - `--where`, which offers the routing modes that the option's own help names (`local`, `cloud`).
- **Local paths** for path-typed parameters and for path-shaped parameter or long-flag names, ignoring Python suffixes such as `_opt` (`*file`, `*path`, `workflow`, `input`, `output`, `--out`, `--gallery`, `--ops`, and similar). Directory-only slots (`*-dir`, `*-root`, `--lib`, `--workspace`) list only folders. ID operands such as `workflow_id` and model-folder names get a placeholder instead.
- **`generate`.** It offers the documented actions (`list`, `schema`, `refresh`, `upload`, `resume`, `consent`) and keeps a `<target>` placeholder for model aliases. `generate` parses its own flags, and `--help-json` does not describe them, so a small table taken from `comfy generate --help` supplies `--download`, `--async`, `--yes`, `--api-key`, `--emit-workflow`, `--emit-ops`, `--actor` and `--base-version`.

Identifiers that cannot be checked locally, and values that would need the server, get a placeholder instead of a network lookup.

## Discovery and safety

Only `--help-json` is ever run. The script does not call or install Typer's completion interface, and it never suggests `--install-completion` or `--show-completion`. The help call:

- closes stdin;
- removes `FORCE_COLOR`, sets `NO_COLOR` and reads UTF-8 output;
- strips ANSI escape sequences before parsing;
- is killed if it runs longer than eight seconds.

A successful result is cached for the session. If `comfy-cli` is not on `PATH`, that is remembered for the session too. A timeout or unreadable output is retried on a later Tab, at most once a minute, so a slow first start does not disable completion. The script does not change the parent PowerShell environment.

## Loading

Load the script directly with `. .\comfy_cli_completer\comfy_cli_completer.ps1`, or load the repository set through CompleterActions. At the top level the script contains only:

- `Set-StrictMode`;
- a `Get-Variable`-guarded cache initialisation;
- function declarations;
- a literal `Register-ArgumentCompleter` call.

This satisfies the CompleterActions strict import grammar.

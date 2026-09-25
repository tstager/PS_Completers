# comfy-cli completer

This standalone PowerShell completer reads the installed `comfy-cli.exe --help` output. It loads nested help only when a command branch is reached, then caches commands, switches, aliases, value markers, and help descriptions for the session. The installed binary used during implementation was `C:\Users\Trent\AppData\Local\Programs\Python\Python314\Scripts\comfy-cli.exe` version 1.21.0.

The script registers the bare and `.exe` command names:

```powershell
Register-ArgumentCompleter -Native -CommandName @('comfy-cli', 'comfy-cli.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-ComfyCli -Word $wordToComplete -Ast $commandAst -Cursor $cursorPosition
}
```

Completion uses the CLI's Rich-formatted `Options` and `Commands` help tables. It covers nested branches such as `model search`, `workflow`, and `build refs`, case-sensitive switch names, separate and `--name=value` option values, positional hints from `Usage`, and local path suggestions for path-shaped slots. Switch tooltips come from help descriptions. The `--where` value suggestions are `local` and `cloud`, as documented by root help. Unverifiable identifiers and server-backed values receive a placeholder instead of a network lookup.

Only `--help` is invoked for discovery; the script does not call or install Typer's completion interface. The Typer setup switches `--install-completion` and `--show-completion` are omitted from suggestions. Help calls use a five-second timeout, closed stdin, UTF-8 child-process output, and a session cache. The script does not change the parent PowerShell environment.

Load directly with `. .\comfy_cli_completer\comfy_cli_completer.ps1`, or load the repository set through CompleterActions. The script's top level contains only `Set-StrictMode`, function declarations, and a literal `Register-ArgumentCompleter` call, satisfying the CompleterActions 2.0.0.0 strict import grammar.

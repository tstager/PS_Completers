# agy PowerShell completer

A standalone, help-driven completer for `agy` and `agy.exe`, requiring PowerShell 7.

```powershell
. .\agy_completer\agy_completer.ps1
```

The repository's `ps_completers.psd1` also includes this script for lazy loading through `Import-CompleterSet`.

## Dynamic discovery

The completer resolves `agy.exe` from PATH and lazily reads its installed help. Validation used `C:\Users\Trent\AppData\Local\agy\bin\agy.exe` on 2026-09-12. That executable has no file-version resource.

- Root commands, switches, and tooltips come from `agy.exe --help`.
- Subcommand catalogs come from `agy.exe help <command>`.
- MCP child options come from the verified `agy.exe mcp <verb> --help` entry points for add, remove, list, enable, and disable.
- Enum values are extracted from help descriptions, with known value kinds for options whose help omits argument markers.
- Local file and directory names are enumerated as you type, including separate and attached option values.

Help is cached per command context for the PowerShell session. Each help process has closed stdin, asynchronous stdout/stderr reads, a two-second exit timeout, and no visible window. Help printed to stderr or with a nonzero exit code is still parsed. Restart PowerShell to refresh the catalogs after updating agy. If help is unavailable, a minimal root command catalog and help option remain available.

## Coverage

Examples to try with Tab:

```text
agy --effort m
agy --effort=m
agy --output-format=
agy --add-dir .\
agy --log-file=.\
agy --json-schema .\
agy mcp add --type h
agy mcp add -H
agy plugin import
agy plugins install .\
agy help mcp
```

Root session options, root command aliases, MCP verbs, plugin verbs, install options, and mic-serve options are context-aware. Case-sensitive matching preserves MCP's distinct `-H` (header) and `-h` (help). `--new-project` is a boolean switch; print and interactive-prompt options take prompt values. Their arities were checked using deliberately invalid argument parsing, without starting a session.

Path completion supports local directories and files, literal brackets, trailing separators, spaces, apostrophes, and quoted attached values. JSON schemas offer both a string placeholder and local files. Plugin import offers `gemini`, `claude`, and local directories; plugin install offers local directories and a `plugin@marketplace` placeholder.

Prompts, model/agent identifiers, conversation/project IDs, server names, plugin names, headers, environment assignments, durations, and microphone addresses use placeholders rather than filesystem fallback. No remote model, agent, MCP-server, marketplace, or conversation listing is invoked. UNC paths are not enumerated.

## CLI quirks and boundaries

Plugin verbs interpret `--help` as an operand, so completion **never invokes plugin verbs**. Their command names and descriptions come solely from parent help. MCP flags must precede the server name; after that position completion offers command/URL and argument placeholders.

New help-listed switches and root commands are discovered automatically. Arbitrary argument types cannot be inferred from descriptions that omit them; the explicit value-kind table covers the verified installed surface.

## Registration

This is the literal registration from the script:

```powershell
Register-ArgumentCompleter -Native -CommandName @('agy', 'agy.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Get-AgyCompletion -Word $wordToComplete -Ast $commandAst -Cursor $cursorPosition
}
```

The top level contains only `Set-StrictMode`, function definitions, and this literal registration. Caches initialize inside functions, satisfying the CompleterActions strict import grammar.

## Validation

Validated in clean `pwsh -NoProfile` sessions through `TabExpansion2`, including both executable names, separate/attached values, command aliases, nested options, mid-line and mid-cursor completion, placeholders, and special-character paths. `Test-CompleterScript` returned no findings; loading and runtime probes left `$Error` empty. The regenerated set contains 170 completers, and the repository gate passed all 173 tests.

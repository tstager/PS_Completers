# pnpm completer

## What it completes / overview

`pnpm_completer.ps1` is a **help-driven** standalone completer for the local
`pnpm` CLI.

pnpm 12 is a clap application, so every node of the command tree prints a
long-form help page with the same layout. The completer parses those pages and
builds its catalog from them:

- root commands, their aliases and their descriptions come from `pnpm help`
- every deeper node comes from `pnpm help <command> [<subcommand> ...]`
- options, their short/long spellings, their value names and their enum values
  come from the `Options:` section of the same page

Nothing is hardcoded, so the surface always matches the installed pnpm.

## Registration and command names

The script registers a native completer for:

```powershell
'pnpm', 'pnpm.cmd', 'pnpm.ps1', 'pn'
```

`pnpm.cmd` and `pnpm.ps1` are registered because PowerShell can resolve pnpm
through several launcher names on Windows. `pn` is registered because pnpm's own
`pnpm completion pwsh` output registers that short alias too.

## How completion works

1. `Set-StrictMode -Version Latest` is enabled.
2. A guarded `$script:PnpmCompletionCache` holds the resolved launcher path and
   the parsed help catalogs. Nothing runs at import time.
3. On the first completion request the launcher is resolved once, preferring
   `pnpm.cmd`, then `pnpm`, then `pnpm.ps1`.
4. The settled argument tokens are taken from `$commandAst.CommandElements`.
   A token that ends at or after the cursor is the word being completed, not a
   settled argument, so an exact subcommand under the cursor still completes.
5. Those tokens are walked to resolve the command path. Options are skipped, and
   a value-bearing option also consumes the token after it, so a universal
   rc-option before the subcommand (`pnpm -r add -`, `pnpm -C . config `) does
   not break subcommand detection. Command aliases resolve to their canonical
   name before the next help page is fetched.
6. Each help page is parsed once and cached for the session, including the
   negative result, so a failing or missing pnpm costs one probe rather than one
   per keystroke.

Help is invoked with standard input closed (`$null | & $launcher help ...`) so a
tool that waits on stdin cannot hang the prompt.

## Option and value completion

Option spellings are matched ordinally, which keeps pnpm's case-distinct short
flags (`-P`, `-D`, `-O`, `-E`, `-C`, `-F`) separate from each other.

Option values come from the help page:

- `[possible values: a, b, c]` and clap's `Possible values:` blocks become enum
  completions with their per-value descriptions as tooltips
  (`pnpm --loglevel <TAB>` -> `silent error warn info debug`)
- a `<DIR>` value name becomes directory completion (`pnpm --dir <TAB>`)
- a `<...FILE>` or `<...PATH>` value name becomes file completion
- anything else becomes a `<VALUE_NAME>` placeholder, so the engine's filename
  fallback does not take over a non-path slot

Both value forms work. The separate form (`pnpm --reporter <TAB>`) offers bare
values; the attached form (`pnpm --reporter=de<TAB>`) keeps the `--reporter=`
prefix on the inserted text.

## Operand slots

A pnpm node either dispatches to subcommands or takes operands. When the
resolved node has no subcommands, the completer returns nothing for a bare word,
so PowerShell's own path completion runs for operands such as
`pnpm add ./local-package`.

## Import-CompleterScript compatibility

The top level stays inside the `CompleterActions` strict import grammar:

- `Set-StrictMode`
- function definitions
- one guarded `$script:` cache initializer
- one literal `Register-ArgumentCompleter -Native` call

`Test-CompleterScript` returns no findings.

## Runtime notes

- Local pnpm version during this revision: `12.4.1`
- Local launcher names observed: `pnpm`, `pnpm.cmd`, `pnpm.ps1`; no `pnpm.exe`
- `pnpm help -a` does not exist in pnpm 12; the root list comes from `pnpm help`
- The completer deliberately does not load `pnpm completion pwsh`. That
  generated script writes `$env:SHELL`, `$env:COMP_LINE` and `$env:COMP_POINT`
  into the session on every keystroke and spawns `pnpm completion-server`, and
  it returns bare strings with no tooltips, short flags or value completion.
- `@()` over a `System.Collections.Generic.List[object]` throws
  `Argument types do not match` on PowerShell 7.6, so the script calls
  `.ToArray()` before wrapping a list.

## Representative validation

Validated in clean `pwsh -NoProfile` sessions with `TabExpansion2`:

- `pnpm ` -> 125 command spellings (aliases included)
- `pnpm -` -> 41 option spellings, `pnpm --` -> 34
- `pnpm ad` -> `add`, `adduser`
- `pnpm add -` -> 70 option spellings including `-P`, `-D`, `-O`, `-E`
- `pnpm --reporter ` -> `default append-only ndjson silent`
- `pnpm --reporter=de` -> `--reporter=default`
- `pnpm --loglevel ` -> `silent error warn info debug`
- `pnpm --dir ` -> directories only
- `pnpm -r add -` and `pnpm -C . config ` -> correct per-command surface
- `pnpm config set` with the cursor at the end of `set` -> `set`
- `pn ` -> the same root command list
- `$x = 1; pnpm ad` -> the same result as at the start of a line
- `$Error` did not grow across the probe set

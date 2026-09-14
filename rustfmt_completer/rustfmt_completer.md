# rustfmt completer

## What it completes / overview

`rustfmt_completer.ps1` registers a standalone native PowerShell completer for `rustfmt` and `rustfmt.exe`.

It is a **help-driven** completer with safe local discovery:

- parses the installed `rustfmt --help` surface for switches
- reads local `rustfmt --help=config` output for config key names
- completes local files and directories for file-bearing arguments

The completion path does not format files or modify configuration.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('rustfmt', 'rustfmt.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # $cursorPosition is an offset into the whole input line, while
    # $commandAst.Extent.Text is command-relative.
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $tokenState = Get-RustfmtTokenState -Line $commandAst.Extent.Text -CursorPosition $relativeCursor
    $currentToken = if ($null -eq $tokenState.CurrentToken) { $wordToComplete } else { $tokenState.CurrentToken }
    $tokensBeforeCurrent = @($tokenState.TokensBeforeCurrent)
    if ([string]::IsNullOrEmpty($wordToComplete) -and -not [string]::IsNullOrEmpty($currentToken)) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent + $currentToken)
        $currentToken = ''
    }
    $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    $state = Get-RustfmtState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.PendingKinds.Count -gt 0) {
        return Get-RustfmtValueSuggestions -ValueKind $state.PendingKinds.Peek() -CurrentToken $currentToken
    }

    $cleanCurrent = Remove-RustfmtOuterQuotes -Value $currentToken
    if ($cleanCurrent -match '^(--?[A-Za-z0-9][A-Za-z0-9\-]*)=(.*)$') {
        $catalog = Get-RustfmtCatalog
        $optionName = $matches[1]
        $attachedValue = $matches[2]
        if ($catalog.AliasLookup.ContainsKey($optionName)) {
            $spec = $catalog.AliasLookup[$optionName]
            if (-not [string]::IsNullOrEmpty($spec.AttachedValueKind)) {
                # Keep the "--opt=" prefix on every suggestion so accepting one
                # does not delete the option name.
                return @(
                    Get-RustfmtValueSuggestions -ValueKind $spec.AttachedValueKind -CurrentToken $attachedValue |
                        ForEach-Object {
                            New-RustfmtCompletionResult -CompletionText ($optionName + '=' + $_.CompletionText) -ResultType $_.ResultType -ToolTip $_.ToolTip -ListItemText $_.ListItemText
                        }
                )
            }
        }

        return @()
    }

    if ($cleanCurrent.StartsWith('-')) {
        return Get-RustfmtSwitchSuggestions -CurrentToken $currentToken
    }

    if ([string]::IsNullOrEmpty($cleanCurrent)) {
        # The operand slot is reachable from a bare TAB: offer the switches and
        # the files rustfmt actually formats.
        return @(
            @(Get-RustfmtSwitchSuggestions -CurrentToken $currentToken) +
            @(Get-RustfmtValueSuggestions -ValueKind 'InputFile' -CurrentToken $currentToken)
        )
    }

    Get-RustfmtValueSuggestions -ValueKind 'InputFile' -CurrentToken $currentToken
}
```

Load it with:

```powershell
. .\rustfmt_completer\rustfmt_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Import-CompleterScript compatibility

The file keeps its top level compatible with `CompleterActions`:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, `try` blocks, helper invocations, or external command calls.

## How completion works

### Switch surface

The completer covers the documented top-level switches, including:

- `--check`
- `--emit`
- `--backup`
- `--config-path`
- `--edition`
- `--style-edition`
- `--color`
- `--print-config`
- `-l`, `--files-with-diff`
- `--config`
- `-v`, `--verbose`
- `-q`, `--quiet`
- `-V`, `--version`
- `-h`, `--help`

### Representative value slots

The completer returns value suggestions for common non-path slots:

- `--emit` → `files`, `stdout`
- `--edition` → `2015`, `2018`, `2021`, `2024`
- `--style-edition` → `2015`, `2018`, `2021`, `2024`
- `--color` → `always`, `never`, `auto`
- `--print-config` → `default`, `minimal`, `current`
- `--help=` / `-h=` → `config`
- `--config` → config keys from installed `rustfmt --help=config`

Every attached value keeps its `--opt=` prefix on the inserted text, so accepting
`--emit=st<TAB>` yields `--emit=stdout` rather than a bare `stdout`.

rustfmt spells the help topic `-h [=TOPIC]`, so the topic is completed only in
the attached form. Offering it as a separate token produced an invalid command
line and suppressed every other suggestion after `-h`.

### The `--config` key and value model

`rustfmt --help=config` right-aligns each key against its type and its default:

```text
                  newline_style [Auto|Windows|Unix|Native] Default: Auto
                                Unix or Windows line endings
```

Keys are harvested by anchoring on the type and the `Default:` column. Matching
only "an indented lowercase word" also matches the first word of every wrapped
description line, which produced fabricated keys such as `Maximum=`, `Whether=`
and `Reorder=`, and missed `short_array_element_width_threshold`, whose long name
pushes it out to column 0.

The same parse supplies the values: a `[A|B|C]` type becomes those enum values
and a `<boolean>` type becomes `true`/`false`, for every key rustfmt documents
rather than a hand-maintained subset. Annotated enum members such as
`2027 (unstable)` are skipped because they are not insertable as one token. A key
with a free-form type gets a `<value>` placeholder, and only while its value is
still empty, so a partly typed value is never overwritten.

`--config` takes a comma-delimited list. Only the segment after the last comma is
completed, and every suggestion carries the segments already typed, so
`--config edition=2021,max_<TAB>` completes to `--config edition=2021,max_width=`.

### Path completion

The completer uses local-only filesystem enumeration for:

- `--config-path` (directories)
- the path argument after `--print-config`
- positional file operands, filtered to directories and `.rs` files, since those
  are the only inputs rustfmt formats

Paths are split on the last separator rather than with `Split-Path`. `Split-Path`
throws on an empty string, which aborted the whole completion scriptblock and
silently degraded every empty path slot to PowerShell's filename fallback; and on
a trailing separator it returns the directory itself as the leaf, which made
tab-walking a tree impossible (`--config-path C:\Windows\<TAB>` offered
`C:\Windows\` instead of its 83 child directories).

### Multi-value switch handling

`--print-config` takes two values in sequence:

```text
--print-config [default|minimal|current] PATH
```

The completer tracks that state so the first value is the mode and the next value becomes a local path completion slot.

## Usage examples

```powershell
rustfmt -<TAB>
rustfmt --color <TAB>
rustfmt --emit <TAB>
rustfmt --print-config <TAB>
rustfmt --print-config current <TAB>
rustfmt --config <TAB>
rustfmt --config edition=<TAB>
rustfmt .\<TAB>
rustfmt.exe --help <TAB>
```

## Runtime notes

- The completer registers both `rustfmt` and `rustfmt.exe`.
- Help/config harvesting is lazy and cached in script scope.
- `--config-path` is treated as a local directory search root because rustfmt searches from that path for `rustfmt.toml`.
- Option spellings are matched ordinally. A case-insensitive match plus a
  case-insensitive `Sort-Object -Unique` collapsed `-V` onto `-v`, so the version
  flag was unreachable and typing it was actively rewritten to verbose.
- `$cursorPosition` is rebased by `$commandAst.Extent.StartOffset` before it is
  applied to the command-relative extent text.
- rustfmt version during this revision: `1.9.0-stable`.

### Representative validation

Clean `pwsh -NoProfile` `TabExpansion2` runs:

- `rustfmt -` 18 → 19 results, gaining `-V`
- `rustfmt --config ` 44 → 28 keys: the 17 fabricated ones are gone and
  `short_array_element_width_threshold` is present
- `rustfmt --config edition=2021,max_` → `edition=2021,max_width=`
- `rustfmt --config-path ` filename fallback → 174 directories
- `rustfmt --config-path C:\Windows\` 1 → 83 child directories
- `rustfmt --print-config current ` filename fallback → real path completion
- `rustfmt --help ` → switches and operands instead of the invalid `config`
- `rustfmt -h=` 0 → `-h=config`; `rustfmt --help=c` → `--help=config`
- `rustfmt --emit=st` → `--emit=stdout`
- `rustfmt ` → switches plus the operand slot, which now fires on a bare TAB
- `$x = 1; rustfmt --con` identical to the same input at the start of a line
- `$Error` did not grow across the probe set; it grew by 2 before

## Limitations

- It does not attempt to inspect project-specific config schemas beyond the installed help output.
- Path completion is local-only and prefix-based.
- Nightly-only and unstable options are not offered, because the switch table is
  static; only the config keys and their values come from live help.

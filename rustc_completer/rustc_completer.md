# rustc completer

## What it completes / overview

`rustc_completer.ps1` registers a standalone native PowerShell completer for `rustc` and `rustc.exe`.

It is a **help-driven** completer with a small amount of safe local discovery:

- parses the installed `rustc -h` surface for documented switches
- reads local `rustc -W help` output for lint names
- reads local `rustc -C help` output for codegen option names
- reads local `rustc --print target-list` output for target triples
- reads local `rustc --print target-cpus` output for CPU names
- completes local files and directories for input/output path slots

The completion path does not compile code or probe remote state.

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('rustc', 'rustc.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokenState = Get-RustcTokenState -Line $commandAst.ToString() -CursorPosition $cursorPosition
    $currentToken = if ($null -eq $tokenState.CurrentToken) { $wordToComplete } else { $tokenState.CurrentToken }
    $tokensBeforeCurrent = @($tokenState.TokensBeforeCurrent)
    if ([string]::IsNullOrEmpty($wordToComplete) -and -not [string]::IsNullOrEmpty($currentToken)) {
        $tokensBeforeCurrent = @($tokensBeforeCurrent + $currentToken)
        $currentToken = ''
    }
    $tokensBeforeCurrent = @($tokensBeforeCurrent | Select-Object -Skip 1)
    $state = Get-RustcState -TokensBeforeCurrent $tokensBeforeCurrent

    if ($state.PendingValueKind) {
        return Get-RustcValueKindSuggestions -ValueKind $state.PendingValueKind -CurrentToken $currentToken
    }

    $cleanCurrent = Remove-RustcOuterQuotes -Value $currentToken
    if ($cleanCurrent -match '^(--[A-Za-z0-9\-]+)=(.*)$') {
        $catalog = Get-RustcCatalog
        $optionName = $matches[1]
        if ($catalog.AliasLookup.ContainsKey($optionName)) {
            $spec = $catalog.AliasLookup[$optionName]
            if ($spec.ValueKind) {
                return Get-RustcValueKindSuggestions -ValueKind $spec.ValueKind -CurrentToken $matches[2]
            }
        }
    }

    if ($cleanCurrent.StartsWith('-') -or [string]::IsNullOrEmpty($cleanCurrent)) {
        return Get-RustcSwitchSuggestions -CurrentToken $currentToken
    }

    if ($state.OperandCount -eq 0) {
        return Get-RustcValueKindSuggestions -ValueKind 'InputFile' -CurrentToken $currentToken
    }

    Get-RustcPathCompletions -CurrentToken $currentToken -FilesOnly $true
}
```

Load it with:

```powershell
. .\rustc_completer\rustc_completer.ps1
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

The completer suggests the documented option surface for common `rustc` flags, including:

- `-h`, `--help`
- `--cfg`
- `--check-cfg`
- `-L`
- `-l`
- `--crate-type`
- `--crate-name`
- `--edition`
- `--emit`
- `--print`
- `-g`
- `-O`
- `-o`
- `--out-dir`
- `--explain`
- `--test`
- `--target`
- `-A`, `--allow`
- `-W`, `--warn`
- `--force-warn`
- `-D`, `--deny`
- `-F`, `--forbid`
- `--cap-lints`
- `-C`, `--codegen`
- `-V`, `--version`
- `-v`, `--verbose`

and the options that only `rustc --help -v` documents but that `rustc` accepts on
every invocation:

- `--extern`
- `--sysroot`
- `--error-format`
- `--json`
- `--color`
- `--diagnostic-width`
- `--remap-path-prefix`
- `--remap-path-scope`

Spellings are matched ordinally, because rustc's short flags are case-distinct in
three pairs: `-L`/`-l`, `-O`/`-o` and `-V`/`-v`. A case-insensitive match followed
by a case-insensitive `Sort-Object -Unique` keeps only one spelling of each pair.

### Representative value slots

The completer gives value suggestions for several non-path slots:

- `--edition` → `2015`, `2018`, `2021`, `2024`, `future`
- `--crate-type` → standard crate kinds
- `--emit` → documented emit kinds
- `--print` → documented `rustc --print` topics
- `--target` → installed target triples from `rustc --print target-list`
- `-A`, `-W`, `-D`, `-F`, `--force-warn` → lint names **and lint groups** from
  `rustc -W help`. That command prints two tables; only the first was being read,
  so `warnings`, `unused`, `nonstandard-style`, `future-incompatible`,
  `rust-2021-compatibility` and the rest of the groups - the values people
  actually pass - were missing. A group's tooltip lists its sub-lints.
- `--cap-lints` → `allow`, `warn`, `deny`, `forbid`
- `-C`, `--codegen` → option names from `rustc -C help`
- `--error-format` → `human`, `json`, `short`
- `--color` → `auto`, `always`, `never`
- `--remap-path-scope` → `macro`, `diagnostics`, `debuginfo`, `coverage`,
  `object`, `all`
- `--json` → `artifacts`, `diagnostic-short`, `diagnostic-rendered-ansi`,
  `diagnostic-unicode`, `future-incompat`
- `--sysroot` → directories

Both value forms work. The attached form keeps its `--opt=` prefix on the
inserted text, so `rustc --emit=<TAB>` yields `--emit=asm` rather than a bare
`asm` that would replace the whole token and delete the option name.

For `-C` / `--codegen`, the completer also recognizes `name=value` forms and suggests values for common options such as:

- `opt-level`
- `target-cpu`
- `target-feature`
- `code-model`
- `lto`
- `panic`
- `strip`
- `split-debuginfo`
- `symbol-mangling-version`
- common boolean switches

### Path completion

The completer uses local-only filesystem enumeration for:

- the INPUT operand, filtered to directories and `.rs` files, and reachable from
  a bare TAB alongside the switch list
- `-L` library search paths
- `-o` output file paths
- `--out-dir` and `--sysroot` directories

Paths are split on the last separator rather than with `Split-Path`. `Split-Path`
throws on an empty string, which aborted the whole completion scriptblock and
silently degraded every empty or bare path slot to PowerShell's filename
fallback; on a trailing separator it also returns the directory itself as the
leaf, so a slot could never descend.

### Placeholder-only slots

Some `rustc` value grammars are free-form or too noisy for reliable live enumeration. For those, the completer intentionally returns placeholder-style hints instead of trying to discover data:

- `--cfg`
- `--check-cfg`
- `-l`
- `--crate-name`
- `--explain`

That avoids falling back to unrelated filesystem completions in non-path slots.

## Usage examples

```powershell
rustc -<TAB>
rustc --edition <TAB>
rustc --target <TAB>
rustc -W <TAB>
rustc -C <TAB>
rustc -C target-cpu=<TAB>
rustc -L <TAB>
rustc .\<TAB>
rustc.exe --print <TAB>
```

## Runtime notes

- The completer registers both `rustc` and `rustc.exe` because both names resolve locally on this machine.
- Help/output harvesting is lazy and cached in script scope, and reads
  `rustc --help -v` so the verbose-only options are covered.
- Help text is treated as authoritative even though native tools do not always use conventional exit codes for help paths.
- `$cursorPosition` is rebased by `$commandAst.Extent.StartOffset` before it is
  applied to the command-relative extent text.
- rustc version during this revision: `1.98.1`.

### Representative validation

Clean `pwsh -NoProfile` `TabExpansion2` runs:

- `rustc -` 31 -> 42 spellings, gaining the eight verbose-only options plus
  `-L`, `-O` and `-V`
- `rustc --extern ` 31 switch names -> `<name>=<path>`
- `rustc --color ` 31 switch names -> `auto always never`
- `rustc --error-format ` 31 switch names -> `human json short`
- `rustc --remap-path-scope ` 31 switch names -> the six scopes
- `rustc --json ` 31 switch names -> the five JSON configs
- `rustc --sysroot ` 31 switch names -> 174 directories
- `rustc -W ` 245 -> 258 values, adding the 13 lint groups
- `rustc -W unu` 24 -> 25, adding the `unused` group
- `rustc --emit=` -> `--emit=asm` ... instead of a bare `asm`
- `rustc --crate-type=b` -> `--crate-type=bin`
- `rustc -L ` and `rustc --out-dir ` filename fallback -> 174 directories
- `$x = 1; rustc --edi` identical to the same input at the start of a line
- `$Error` did not grow across the probe set; it grew by 2 before

## Limitations

- The completer does not parse every possible nested `rustc` value grammar; the
  comma-separated `--emit`/`--crate-type`/`--print` lists and the `=FILE` suffix
  are not modelled.
- `-L` and `-l` support richer syntaxes than simple directory/library-name hints; the completer keeps those slots conservative.
- Path completion is local-only and prefix-based.

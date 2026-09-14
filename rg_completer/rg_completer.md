# rg completer

## What it completes / overview

`rg_completer.ps1` registers a standalone native PowerShell completer for `rg` and `rg.exe`.

It is a help-driven completer that:

- parses the local `rg.exe --help` surface once per session and harvests the negation and alias spellings ripgrep only documents in prose (`--no-*`, `--maxdepth`) from `rg.exe --generate complete-powershell`
- caches file type names from `rg.exe --type-list`
- suggests both short and long options
- supports inline `--option=value` completion and attached short values such as `-tTYPE`, `-A5` or `-iA5`, plus extension of boolean short clusters such as `-iF`
- provides targeted enum hints for `--engine`, `--color`, `--sort`, `--generate`, `--hyperlink-format`, and common encodings
- completes real filesystem paths for path-bearing operands and options like `-f` and `--ignore-file`
- suppresses noisy filesystem fallback for regex, glob, replacement, separator, and command-valued slots with placeholder-oriented suggestions

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'rg', 'rg.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -isnot [string]) {
        $wordToComplete = [string]$wordToComplete
    }

    Initialize-RgCompletionCatalog
    $catalog = Get-RgCompletionCatalog

    # The AST extent stops at the last token, so an empty $wordToComplete is the only reliable
    # signal that the cursor sits after whitespace and a fresh slot is being completed.
    $currentToken = if ([string]::IsNullOrEmpty($wordToComplete)) {
        ''
    } else {
        Get-RgCurrentToken -Line $commandAst.Extent.Text -CursorPosition ($cursorPosition - $commandAst.Extent.StartOffset) -Fallback $wordToComplete
    }
    $tokensBeforeCurrent = Get-RgArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition
    $context = Get-RgCompletionContext -TokensBeforeCurrent $tokensBeforeCurrent

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionKey = Get-RgCanonicalOptionKey -Token $matches[1]
        $valuePrefix = $matches[2]
        if ($catalog.OptionByToken.ContainsKey($optionKey)) {
            $optionSpec = $catalog.OptionByToken[$optionKey]
            if ($optionSpec.ValueKind) {
                return @(Get-RgValueCompletions -OptionSpec $optionSpec -CurrentValue $valuePrefix -Prefix ($matches[1] + '='))
            }
        }
    }

    if ($currentToken.Length -gt 2 -and -not $context.EndOfOptions) {
        $cluster = Resolve-RgShortToken -Token $currentToken
        if ($cluster) {
            if ($cluster.ValueOption) {
                return @(Get-RgValueCompletions -OptionSpec $cluster.ValueOption -CurrentValue $cluster.Value -Prefix $cluster.Prefix)
            }

            return @(Get-RgShortClusterCompletion -Cluster $cluster)
        }
    }

    if ($context.PendingOption) {
        return @(Get-RgValueCompletions -OptionSpec $context.PendingOption -CurrentValue $currentToken)
    }

    if ($currentToken.StartsWith('-') -and -not $context.EndOfOptions) {
        return @(Get-RgOptionCompletions -CurrentWord $currentToken)
    }

    @(Get-RgPositionalCompletions -CurrentWord $currentToken -Context $context)
}
```

Load it with:

```powershell
. .\rg_completer\rg_completer.ps1
```

The script also enables:

```powershell
Set-StrictMode -Version 2.0
```

## Import and runtime behavior

The completer keeps its top level import-safe for `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal native `Register-ArgumentCompleter` call

All help parsing, command resolution, and type discovery happen lazily from helper functions during completion instead of at import time.

## How completion works

### Help-driven option catalog

Initialization captures `rg.exe --help` and parses the option synopsis lines into a cached option catalog. That gives the completer a local view of the installed ripgrep build without hard-coding the entire flag set.

### Dynamic type completion

The completer also captures `rg.exe --type-list` and caches the discovered type names. Those are used for:

- `-t`, `--type`
- `-T`, `--type-not`
- `--type-clear`

### Operand routing

The completer tracks ripgrep's main positional modes:

- normal search mode expects a first positional pattern
- `-e` / `--regexp` and `-f` / `--file` switch ripgrep into path-only positional mode
- `--files` also uses path-only positionals
- terminal modes such as `--type-list`, `--version`, and `--pcre2-version` suppress normal positional suggestions

### Placeholder-only slots

Free-form slots such as regex patterns, globs, replacements, separators, and preprocessor commands intentionally return placeholders or the typed value instead of generic filesystem completions.

## Usage examples

```powershell
rg 
rg -
rg --sort=
rg --engine=
rg --type=
rg -tps
rg foo .\
rg -f .\
```

## Dependencies or external command expectations

- Expects `rg.exe` or `rg` to be resolvable if help data and type names should be harvested
- Falls back to placeholder-oriented completion when runtime discovery is unavailable
- Filesystem completion depends on local filesystem access

## Limitations / notes

- Short clusters are decomposed left to right against the live catalog; the first value-taking flag ends the cluster and the rest of the token is its value (`-iA5`, `-tpy`). A cluster with an unknown letter falls back to plain option matching.
- Encoding suggestions use a curated common set instead of enumerating every WHATWG label.
- `--colors` and `--type-add` use representative examples and placeholders rather than trying to fully validate ripgrep's mini-languages during completion.

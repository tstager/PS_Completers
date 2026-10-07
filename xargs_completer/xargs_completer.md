# xargs completer

## What it completes / overview

`xargs_completer.ps1` registers a standalone native PowerShell completer for `xargs` and `xargs.exe`.

Two `xargs` binaries commonly coexist on Windows (the uutils coreutils package and Git's GNU findutils build), and their option surfaces differ: uutils 0.10.0 has `-h`/`-V` but rejects `-o`, `-p`, `--process-slot-var` and `--show-limits`. The completer therefore reads the option list from the `--help` of whichever `xargs` resolves first on `PATH`, and keeps a hand-written GNU findutils table as the fallback when no `xargs` is installed or its help cannot be parsed.

It covers:

- short and long options with their help descriptions as tooltips
- value slots for the argument file (`-a`/`--arg-file`, path completion), delimiter, numeric limits, replace token, EOF string and `--process-slot-var`
- the attached form `--arg-file=path`, keeping the option prefix on every suggestion
- command-name completion for the command operand, from a cached list of applications on `PATH`

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'xargs', 'xargs.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $tokensBeforeCurrent = @()
    foreach ($element in $commandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $cursorPosition) {
            $tokensBeforeCurrent += $element.Extent.Text
        }
    }

    $context = Get-XargsCompletionContext -CurrentToken $wordToComplete -TokensBeforeCurrent $tokensBeforeCurrent
    if ($context) {
        return Get-XargsValueSuggestions -OptionSpec $context.OptionSpec -CurrentValue $context.ValueText -Prefix $context.Prefix
    }

    if (-not [string]::IsNullOrWhiteSpace($wordToComplete) -and $wordToComplete.StartsWith('-')) {
        return Get-XargsOptionSuggestions -CurrentToken $wordToComplete
    }

    if (-not (Test-XargsCommandOperandSeen -TokensBeforeCurrent $tokensBeforeCurrent)) {
        return Get-XargsCommandSuggestions -CurrentValue $wordToComplete
    }

    @()
}
```

Load it with:

```powershell
. .\xargs_completer\xargs_completer.ps1
```

It also enables `Set-StrictMode -Version 2.0`.

## Completion behavior

### Options

`Get-XargsOptionSpecs` locates `xargs` by scanning `PATH` in `PATHEXT` order, runs `xargs --help` once (stdin closed, output drained asynchronously, killed after 5 s, ANSI-stripped) and parses the option column. Value kinds and tooltips for known options come from the static table; an option the table does not know gets a `<metavar>` placeholder when its help shows a mandatory value. The result is cached per session, keyed on `PATH` and the binary's last-write time, so a cold Tab costs about 150-200 ms and a warm one a few milliseconds. With uutils 0.10.0 that yields:

- `-a`/`--arg-file`, `-d`/`--delimiter`, `-x`/`--exit`, `-n`/`--max-args`, `-L`/`--max-lines`, `-l`, `-P`/`--max-procs`, `-r`/`--no-run-if-empty`, `-0`/`--null`, `-s`/`--max-chars`, `-t`/`--verbose`, `-i`/`--replace`, `-I`, `-E`, `-e`/`--eof`, `-h`/`--help`, `-V`/`--version`

The static fallback (GNU findutils 4.x) is:

- `-0`/`--null`, `-a`/`--arg-file FILE`, `-d`/`--delimiter CHAR`, `-E END`, `-e`/`--eof[=END]`, `-I R`, `-i`/`--replace[=R]`, `-L`/`--max-lines N`, `-l[N]`, `-n`/`--max-args N`, `-o`/`--open-tty`, `-P`/`--max-procs N`, `-p`/`--interactive`, `--process-slot-var VAR`, `-r`/`--no-run-if-empty`, `-s`/`--max-chars N`, `--show-limits`, `-t`/`--verbose`, `-x`/`--exit`, `--help`, `--version`

### Value slots

- `-a`/`--arg-file` uses path completion; `--arg-file=to` keeps the prefix and completes `--arg-file=tools\`
- other value-bearing options show a placeholder such as `<max>`, `<R>` or `<var>` when the slot is empty, and nothing once a value is typed

### Command operand

`Test-XargsCommandOperandSeen` scans the completed tokens left to right, consuming each option and its value (attached or separate), and reports whether a command operand has already appeared. Until it has, the current word is the command and `Get-XargsCommandSuggestions` offers application names from a list cached per `PATH` value. After the command, the completer returns nothing so PowerShell's default completion applies to the command's own arguments.

## Usage examples

```powershell
xargs
xargs gr
xargs -n 5 gre
xargs --arg-file=to
xargs -I {} ec
```

Expected behavior:

- the bare command lists applications on `PATH` (about 1400 entries, under half a second warm)
- `gr` and `-n 5 gre` complete `grep` and its siblings
- `--arg-file=to` completes paths with the prefix kept
- after `-I {}` the next word is the command

## Dependencies or external command expectations

- The option catalog is read from the resolved `xargs --help` (uutils or GNU findutils); the built-in fallback is authored from `xargs --help` of GNU findutils 4.x.
- Command-name suggestions depend on `Get-Command -CommandType Application` and are cached until `PATH` changes.

## Limitations / notes

- PowerShell does not invoke native completers for an empty word directly after a `{}` script-block token, so `xargs -I {} ` followed by Tab shows nothing until a letter is typed.
- Option lookup is ordinal, so `-P`/`-p`, `-L`/`-l`, `-I`/`-i` and `-E`/`-e` resolve to their own specs (`xargs -P ` offers `<max>`; with GNU findutils `xargs -p ` offers the command and typing `-p` lists only `-p`).
- `-i`/`--replace` take R only attached (`-iR`, `--replace=R`; otherwise `{}`), so the token after `-i` is the command: `xargs -i ` offers command names and `xargs -i ls ` does not offer them again. The resolved uutils findutils 0.10.0 consumes the next token for `-e` and `-l` (GNU only accepts those attached), so the completer keeps offering a placeholder in the slot after them.

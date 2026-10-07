# du completer

## What it completes / overview

`du_completer.ps1` registers a standalone native PowerShell completer for `du` and `du.exe`.

Its static option catalog models GNU coreutils `du`. On first use it reads `du --help` from the `du` that resolves on `PATH` (GNU from Git for Windows, or uutils coreutils), refreshes the descriptions and adds any options the static table lacks, such as uutils' `-A`, `-v`/`--verbose` and `-V`. Sysinternals `du` is not modelled.

The completer covers:

- every short and long option of GNU `du`, plus those the installed `du` documents, offered case-sensitively so `-B`/`-b`, `-D`/`-d`, `-H`/`-h`, `-L`/`-l`, `-S`/`-s` and `-X`/`-x` stay distinct
- values for `-d`/`--max-depth`, `-B`/`--block-size`, `-t`/`--threshold`, `--time`, `--time-style`, `--exclude`, `--files0-from` and `-X`/`--exclude-from`, in the separate and the attached `--opt=value` form
- clustered short flags (`-sh`, `-sd 1`, `-sd1`), as GNU `du` parses them with getopt
- file and directory completion for the operand slots (directories first)
- quoted paths, including an unterminated opening quote

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'du', 'du.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Du -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\du_completer\du_completer.ps1
```

The script also enables `Set-StrictMode -Version 2.0`.

## Import-CompleterScript compatibility

The top level contains `Set-StrictMode`, one `Get-Variable`-guarded catalog initialisation, function definitions and the literal registration call, which the CompleterActions strict import grammar accepts.

## How completion works

- `Initialize-DuCompletionCatalog` builds the option catalog from a static table of GNU options with their value kinds, then overlays `du --help` (run with stdin closed): a known option takes the help description, and an unknown one is added with its value kind taken from its partner option or from the placeholder (`SIZE`, `N`, `FILE`/`F`, `PATTERN`, `WORD`, `STYLE`, written GNU-style as `--opt=SIZE` or uutils-style as `--opt <SIZE>`; a bracketed `[=WORD]` is an optional value offered only in the attached form). Lookups use an ordinal comparer.
- `Get-DuState` scans the completed tokens, records which options were used (ordinal, so `-s` does not hide `-S`), and notes when the previous option still expects a value. An attached `--opt=value` token counts as a complete option.
- `Get-DuShortFlagCluster` splits a cluster such as `-sh` or `-sd1` into its flags: every letter is a flag until one that takes a value, which consumes the rest of the word or, when it ends the word, the next word. A completed `-sd ` therefore offers depth values, and `-sd1 ` does not.
- `Complete-Du` answers, in order: values for an attached `--opt=` word, values for a pending option, cluster extensions for a word of two or more short flags (`-sh` offers `-sha`, `-shc`, ... for each unused short flag; a cluster ending in a value-taking flag is not extended), options for a word starting with `-`, and file and directory completion for everything else. An empty operand slot also lists the unused options.
- Value kinds: `Levels` offers `0 1 2 3 5 10`; `Size` offers `1 1K 1M 1G K M G`; `TimeWord` offers `atime access use ctime status`; `TimeStyle` offers `full-iso long-iso iso +%Y-%m-%d`; `File` (`-X`/`--exclude-from`) offers files and directories, and `FileOrStdin` (`--files0-from`) offers `-` (standard input) before them. In the attached form the `--opt=` prefix is kept.
- Paths containing whitespace or an argument-mode metacharacter (`{ } ( ) ; , | & < > ' "`, a backtick, `$`, or a leading `@`/`#` on a bare operand) are emitted double-quoted with backtick, `"` and `$` escaped; an attached value such as `--exclude-from="a b.txt"` reaches `du` as one argument.

## Representative validation scenarios

```powershell
du -
du --m
du -d
du --max-depth=
du --time=
du -h
du -sh
du -sd 
```

Expected behavior:

- `-` lists all 44 static options, plus `-A`, `-v`, `--verbose` and `-V` when uutils `du` is installed, with their help descriptions
- `--m` completes `--max-depth`; `-d ` and `--max-depth=` list the depth hints
- `--time=` lists the time words with the `--time=` prefix kept
- `-h ` lists the directories, then the files, of the current location
- `--files0-from=` lists `--files0-from=-` and then the paths; `--exclude-from=.gi` completes `--exclude-from=.github\` and `--exclude-from=.gitignore`
- `-sh` lists `-sh0`, `-sha`, `-shB`, ... for every unused short flag; `-sd ` lists the depth hints

## Dependencies or external command expectations

- `du` or `du.exe` on `PATH` to refresh descriptions; the static catalog is used as-is otherwise
- filesystem access for path completion

## Limitations / notes

- Hidden files and directories are not listed, matching `Get-ChildItem` without `-Force`.

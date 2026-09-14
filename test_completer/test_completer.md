# test completer

## What it completes / overview

test_completer.ps1 registers a standalone native PowerShell completer for test and test.exe.

It is a **static** completer. `test(1)` has no help output by design: POSIX requires it to
treat `--help` and `--version` as ordinary nonempty STRINGs, and both installed builds answer
them with an empty stdout and exit 0. The operator catalog is therefore transcribed from the
GNU coreutils `test` help that the sibling `[` binary prints, and verified against the
`test.exe` that `Get-Command` resolves (`C:\Program Files\coreutils\bin\test.exe`, the uutils
coreutils build). No process is spawned during completion.

The completer covers:

- operator-name suggestions for every documented operator, each with its real GNU description
- typed operand values for the operators whose argument is not a path
- filesystem path completion for the FILE operand slots
- a simple import-safe registration shape that can be loaded directly in PowerShell

## Operator catalog

- file tests: `-b`, `-c`, `-d`, `-e`, `-f`, `-g`, `-G`, `-h`, `-k`, `-L`, `-N`, `-O`, `-p`,
  `-r`, `-s`, `-S`, `-u`, `-w`, `-x`
- terminal test: `-t`
- string tests: `-n`, `-z`, `=`, `!=`
- integer comparisons: `-eq`, `-ne`, `-ge`, `-gt`, `-le`, `-lt`
- binary file comparisons: `-ef`, `-nt`, `-ot`
- logic and grouping: `!`, `-a`, `-o`, `(`, `)`

`-l STRING` (the GNU "length of STRING" integer form) is deliberately **not** offered: the
resolved uutils build rejects it (`test -l abc` exits 2 with `extra argument 'abc'`).

## Registration and command names

The script ends with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'test', 'test.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Test -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

Load it with:

```powershell
. .\test_completer\test_completer.ps1
```

## Import-CompleterScript compatibility

The top level stays compatible with `CompleterActions` `Import-CompleterScript` by limiting it to:

- `Set-StrictMode`
- function definitions
- one literal `Register-ArgumentCompleter -Native` call

There are no top-level assignments, loops, helper invocations, or runtime setup work that would make the script importer-incompatible.

## How completion works

- Operator names come from one static catalog cached in script scope; each entry carries the
  GNU one-line description as its tooltip and the operand kind its value slot expects.
- Operator matching is case-sensitive, so case-distinct short options such as `-g`/`-G`,
  `-s`/`-S`, `-n`/`-N` and `-o`/`-O` are all offered.
- The operator preceding the cursor owns its value slot: `-t` offers `0`, `1`, `2` and `<fd>`;
  `-eq`, `-ne`, `-ge`, `-gt`, `-le` and `-lt` offer `<integer>`; `-n`, `-z`, `=` and `!=` offer
  `<string>`. FILE operators fall through to path completion.
- The non-hyphen operators `!`, `=`, `!=`, `(` and `)` are matched as operators before the word
  is treated as a path. PowerShell parses a bare `(` or `)` as a sub-expression and never calls
  a native completer for it, so those two are reachable in their quoted form (`test '('`), and
  the completer echoes the quoted spelling back.
- Operand slots use filesystem path completion, with wildcard characters in the typed text escaped.
- An unquoted path containing a space arrives split across several words. The completer walks
  left over the plain operands already on the line, rejoining them until the candidate resolves
  to a real directory, and then strips that rejoined prefix from every completion because the
  engine only replaces the last whitespace-delimited fragment.
- The current word is located by rebasing the cursor to the command's start offset, so completion works when the command is not the first statement on the line.
- The catalog probe uses `-ErrorAction Ignore` so a cold load adds nothing to `$Error`.

## Representative validation scenarios

```powershell
test -
test -t
test -e C:\Program Files\
test '('
```

Expected behavior:

- `-` shows every hyphen operator with its GNU description
- `test -t ` offers the file descriptors `0`, `1`, `2` and `<fd>` instead of filenames
- `test -e C:\Program Files\` offers `Files\<child>` completions instead of nothing
- `test '('` offers the quoted grouping operators
- the completer remains importable through `Import-CompleterScript`

## Notes

- This completer is intentionally focused on the file and string test workflow.
- The implementation stays aligned with the repository's import-safe completer pattern.

# fd completer

## What it completes / overview

`fd_completer.ps1` registers a native PowerShell completer for `fd` and `fd.exe`.

It is help-driven with a static floor: the script seeds the catalog from a built-in fd 10.x option table (which is also the only source for the override flags clap does not print, such as `--no-hidden`, `--ignore`, `--relative-path`, `--no-follow`, `--has-results`), then parses the locally installed `fd.exe --help` output over it and layers static value hints on top for enum and path-bearing options. The catalog only latches once the help produced specs, so a session whose first completion ran while `fd` was unresolvable recovers later.

## Registration and command names

The script registers:

- `fd`
- `fd.exe`

with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('fd', 'fd.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Fd -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}
```

## Supported completion behavior

- Switch completion comes from the installed `fd.exe --help` output merged over the static seed; only clap's option rows (indented 2-6 spaces) start a spec, so the example lines inside descriptions (`--exclude node_modules`, `--newer 2018-10-27`) no longer create duplicate or mis-described options, and each token is emitted once with canonical names before the alias/override flags.
- `--color` offers `auto`, `always`, and `never` in the separate and the attached form (`--color=al` -> `--color=always`, `-c=`). `--hyperlink[=<when>]` and `--strip-cwd-prefix[=<when>]` take their value attached only, so `fd --strip-cwd-prefix pat ` treats `pat` as the pattern and completes paths.
- `--type` offers both short and long file-type selectors such as `f`, `file`, `d`, `directory`, `x`, and `executable`.
- `-C`/`--base-directory` and `--search-path` complete directories only (the binary rejects a file there); `--ignore-file` completes files and directories.
- `--format` offers the template placeholders fd substitutes: `{}`, `{/}`, `{//}`, `{.}`, `{/.}`, `{{`, `}}`.
- `-x`/`--exec` and `-X`/`--exec-batch`: the next word is a program name (application names on `PATH`, cached per `PATH` value, plus the placeholders); every later word up to a `\;` terminator is the command's tail and offers the placeholders plus path completion instead of fd's options.
- `--extension`, `--size`, `--changed-within`, and `--changed-before` offer conservative example values and placeholders.
- After the first positional pattern has been supplied, subsequent positional arguments complete as search paths.

## Dependencies or external command expectations

The completer depends on the installed `fd` / `fd.exe` help output for the option list. It does not execute searches during completion, and it does not perform network operations.

## Usage / loading example

```powershell
. .\fd_completer\fd_completer.ps1
```

Example scenarios:

```powershell
fd --<TAB>
fd --type <TAB>
fd --color <TAB>
fd --base-directory <TAB>
fd pattern .\<TAB>
```

## Limitations / notes

- Enum-like value suggestions are static hints layered over the help-driven option catalog.
- The exec tail is recognised by position only; the command's own options are not modelled, and PowerShell does not invoke a native completer directly after a `{}` script-block token.
- The first positional slot is treated as a search-pattern slot unless the current input already looks like a path.

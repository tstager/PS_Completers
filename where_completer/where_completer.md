# where completer

## What it completes / overview

`where_completer.ps1` registers a native PowerShell completer for `where.exe`, and also registers the bare command name `where`.

The script is intentionally small and focused:

- it initializes a script-scoped catalog once,
- it tries to read `where.exe /?` and extract switch tokens from the built-in help text,
- and it adds special handling for the `/R` option because that option expects a path.

## Registration and command names

The script registers a native completer for:

- `where`
- `where.exe`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName @('where.exe', 'where') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-Where -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

In a default PowerShell session, the built-in read-only alias `where` still resolves to `Where-Object`, so that alias keeps its normal shell semantics and completion behavior. Completion therefore requires the `where.exe` spelling; the native `where` registration only becomes relevant in sessions where the alias has been intentionally removed or overridden and `where` resolves to the native executable.

## How completion works

### 1. One-time catalog initialization

`Initialize-WhereCompletion` populates `$script:WhereCompletionCatalog` with:

- `Switches` (token plus description, used as the tooltip)
- `PathOptions`

The documented switch set (`/R`, `/Q`, `/F`, `/T`, `/?`) is always seeded first; live help can only add to it, so a missing or unreadable `where.exe` never empties the catalog. The initialization runs only once per session.

### 2. Help-text parsing

The script tries to execute:

```powershell
where.exe /?
```

`Get-WhereSwitchTokensFromLines` scans the returned lines and extracts switch tokens that look like:

- `/R`
- `/Q`
- `/F`
- `/T`
- `/?`

Any token the parser finds that is not already in the seeded list is added on top of it.

### 3. Token and context detection

`Get-WhereCurrentToken` reconstructs the current token from the command line when PowerShell does not provide a usable `$wordToComplete`.

`Get-WhereExpectedValueOption` only recognizes one option as value-taking:

- `/R`

### 4. Path completion for `/R`

When the previous token is `/R`, `Get-WherePathCompletions` uses `Get-ChildItem -Directory` to complete directories, since `/R` names the directory the recursive search starts from.

The implementation:

- trims existing quotes,
- splits the typed text on its last directory separator instead of using `Split-Path`, so `.\`, `C:\` and a trailing separator all list that directory's children,
- keeps exactly the prefix the user typed (relative input stays relative),
- appends a directory separator to every completion,
- re-adds quotes when the input was already quoted or the completed path contains spaces,
- offers a `<directory>` placeholder when nothing matches, so PowerShell's file fallback does not offer a file in a directory-only slot.

### 5. Pattern operand completion

Any other word is the `pattern` operand. The completer offers, prefix-filtered:

- `*.<ext>` wildcard patterns derived from `%PATHEXT%` (plus `*.dll`, the example from the tool's own help),
- once at least one character is typed, executable names found on `%PATH%` whose extension is in `%PATHEXT%` (cached per `PATH` value, enumerated once per session).

Words containing `\`, `/`, `:` or `$` (explicit paths, `path:pattern`, `$env:pattern`) are left to PowerShell's own completion.

## Key completion behaviors / supported values

### Switch completion

If the current token starts with `/`, the completer filters the available switches by prefix.

Example:

```powershell
where.exe /<TAB>
```

### Blank-argument completion

If the current token is empty, the completer offers all known switches followed by the `*.<ext>` patterns.

### `/R` path completion

If the previous completed token is `/R`, the completer switches to filesystem completion for the next token.

Example:

```powershell
where.exe /R C:\Win<TAB>
```

### Pattern completion

```powershell
where.exe not<TAB>      # notepad.exe and other %PATH% executables starting with "not"
where.exe /R C:\Windows *.<TAB>
```

## Dependencies or external command expectations

This completer expects `where.exe` to be available.

Its preferred source of switch data is the command's own built-in help text. If that help call fails, the script uses the fallback switch list embedded in the file.

## Usage / loading example

Dot-source the script:

```powershell
. .\where_completer.ps1
```

Example completion scenarios:

```powershell
where.exe <TAB>
where.exe /<TAB>
where.exe /R <TAB>
where.exe /R "C:\Program Files\"<TAB>
```

## Limitations / notes

- Only `/R` is treated as a value-taking option in the current implementation.
- Executable-name completion covers `%PATH%`; the current directory (which `where.exe` also searches) is not enumerated.
- In default PowerShell, bare `where` still resolves to the `Where-Object` alias rather than the native executable, so type `where.exe` to get completion.


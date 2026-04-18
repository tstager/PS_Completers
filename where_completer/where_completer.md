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
Register-ArgumentCompleter -Native -CommandName @('where.exe', 'where') -ScriptBlock { ... }
```

In a default PowerShell session, the built-in read-only alias `where` still resolves to `Where-Object`, so that alias keeps its normal shell semantics and completion behavior. The native `where` registration only becomes relevant in sessions where the alias has been intentionally removed or overridden and `where` resolves to the native executable.

## How completion works

### 1. One-time catalog initialization

`Initialize-WhereCompletion` populates `$script:WhereCompletionCatalog` with:

- `GlobalSwitches`
- `PathOptions`

The initialization runs only once per session.

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

If help parsing fails, the script falls back to a hard-coded switch list:

- `/R`
- `/Q`
- `/F`
- `/T`
- `/?`

### 3. Token and context detection

`Get-WhereCurrentToken` reconstructs the current token from the command line when PowerShell does not provide a usable `$wordToComplete`.

`Get-WhereExpectedValueOption` only recognizes one option as value-taking:

- `/R`

### 4. Path completion for `/R`

When the previous token is `/R`, `Get-WherePathCompletions` uses `Get-ChildItem` to complete filesystem paths.

The implementation:

- trims existing quotes,
- preserves relative input where possible,
- appends a directory separator to directory completions,
- re-adds quotes when the input was already quoted or the completed path contains spaces.

## Key completion behaviors / supported values

### Switch completion

If the current token starts with `/`, the completer filters the available switches by prefix.

Example:

```powershell
where.exe /<TAB>
```

### Blank-argument completion

If the current token is empty, the completer offers all known global switches.

### `/R` path completion

If the previous completed token is `/R`, the completer switches to filesystem completion for the next token.

Example:

```powershell
where.exe /R C:\Win<TAB>
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

- The script only completes switches and the `/R` path argument.
- It does not attempt to complete filename patterns or other non-switch arguments to `where.exe`.
- Only `/R` is treated as a value-taking option in the current implementation.
- In default PowerShell, bare `where` still resolves to the `Where-Object` alias rather than the native executable.


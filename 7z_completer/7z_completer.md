# 7z completer

## What it completes / overview

`7z_completer.ps1` registers a native PowerShell argument completer for `7z` and `7z.exe`.

This completer is dynamic: it builds its completion catalog from the installed 7-Zip help output (`7z --help`) and caches the parsed results in `$script:SevenZipCompletionCatalog`.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command names:
  - `7z`
  - `7z.exe`

The script discovers available 7-Zip command verbs from the `<Commands>` section of the help text, so the exact command list comes from the installed 7-Zip build rather than a hardcoded table.

## How completion works

The script:

1. Resolves a usable `7z` executable with `Get-Command 7z.exe, 7z`.
2. Runs `7z --help`.
3. Normalizes the help text so the `Usage:`, `<Commands>`, and `<Switches>` sections are easier to parse.
4. Extracts:
   - command verbs from `<Commands>`
   - switch tokens from `<Switches>`
   - enumerated value hints from switch definitions that expose values in `{...}` or `[...]`
5. Caches the parsed catalog for later completion requests.

At completion time it inspects the current command line, determines:

- the active 7-Zip command, if one has already been entered
- whether `--` has been used to terminate option parsing
- whether the current token is:
  - a command
  - a switch
  - a switch value entered separately
  - a switch value entered inline (for example, a switch immediately followed by its value)

## Key completion behaviors / supported values

- Before a command is chosen, it offers:
  - discovered 7-Zip command verbs
  - discovered switch tokens
- After a command is chosen, it continues to offer switches.
- If a switch has enumerated values in the parsed help output, those values are completed.
- Value completion works both for:
  - separate switch values
  - inline switch values
- The script treats these switches as directory-valued and completes directories for them:
  - `-o`
  - `-w`
- Directory completions:
  - preserve relative vs. absolute style where possible
  - append a trailing directory separator
  - quote paths when needed
  - can preserve inline switch prefixes such as `-o`
- If `--` appears earlier on the command line, switch and switch-value completion is suppressed after that point.

## Dependencies or external command expectations

- Requires `7z` or `7z.exe` to be available on `PATH`.
- Requires the installed 7-Zip help output to contain recognizable `<Commands>` and `<Switches>` sections.
- Does not ship its own command catalog; it depends on the external tool for discovery.

## Usage / loading example

```powershell
. .\7z_completer.ps1
```

Example scenarios after loading:

```powershell
7z <Tab>
7z a -<Tab>
7z a -o<Tab>
```

## Limitations / notes

- If `7z` cannot be resolved, the completer returns no suggestions.
- If help parsing fails, the catalog remains effectively empty.
- Only `-o` and `-w` get directory completion from this script.
- The script does not add custom completion for archive contents or arbitrary positional file arguments.

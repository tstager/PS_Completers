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
   - command verbs and their one-line descriptions from `<Commands>` (the description becomes the tooltip)
   - switch tokens and their descriptions from `<Switches>`
   - the value grammar printed after each switch, parsed as nested `{required}` / `[optional]` groups with `|` alternatives: `-bs{o|e|p}{0|1|2}`, `-scs{UTF-8|...|{id}}`, `-v{Size}[b|k|m|g]`, `-u[-][p#]...` and `-i[r[-|0]][m[-|2]][w[-]]{@listfile|!wildcard}` all parse; a lone `{Directory}`, `{Type}`, `{name}` or `[N]` is a metavariable placeholder rather than a value
5. Caches the parsed catalog for later completion requests.
6. On first use of `-t` or `-stx`, runs `7z i` and caches the archive format names from its `Formats:` table.

At completion time it inspects the current command line, determines:

- the active 7-Zip command, if one has already been entered
- whether `--` has been used to terminate option parsing
- whether the current token is:
  - a command
  - a switch
  - a switch value entered inline (7-Zip only accepts a value attached to its switch, as in `-tzip` or `-oC:\out`, so no space-separated value form is offered)
  - an operand, which for every 7-Zip command is the archive name followed by file names

## Key completion behaviors / supported values

- Before a command is chosen, it offers:
  - discovered 7-Zip command verbs
  - discovered switch tokens
- After a command is chosen, an operand slot completes files and directories; switches are still offered for an empty word and whenever the word starts with `-`.
- If a switch has a value grammar in the parsed help output, the next step of that grammar is completed inline: `-bs` offers `-bso0` ... `-bsp2`, `-r` offers `-r-` and `-r0`, `-sns` offers `-sns-`, `-v10` offers `-v10b|k|m|g`, `-i` offers the `r`/`m`/`w` modifiers plus `@<listfile>` and `!<wildcard>`, and once `@` or `!` has been typed (`-i@`, `-x!`, `-ir@lists`) the rest completes as a file path with the switch prefix kept. A switch whose only documented value is a metavariable (`-p{Password}`, `-sfx[{name}]`) keeps completing its own name.
- `-mx`, `-mmt` and `-m` complete from a static table of the documented method parameters: levels for `-mx` (`-mx9` or `-mx=9`), thread counts for `-mmt`, and `-m<key>=` parameters such as `-m0=LZMA2`, `-ms=on`, `-mhe=on`, `-md=64m`, `-mfb=64`.
- `-t` and `-stx` complete the archive format names reported by `7z i`.
- A bare `@` (or `@` after a command) completes a `@listfile` path.
- The current word is recovered from the command text rather than from PowerShell's parsed elements, so `-oC:\Users\Tr` and `-wD:` keep their switch prefix even though PowerShell splits a token containing a drive colon.
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
- Operand slots complete every file and directory; they are not filtered down to archive extensions, and the script does not list the contents of an archive.

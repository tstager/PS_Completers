# gawk completer

## What it completes / overview

`gawk_completer.ps1` registers a standalone native PowerShell argument completer for GNU awk command lines.

The script uses a hybrid, help-validated design rather than a subcommand tree:

- it keeps an embedded option-definition table with value metadata,
- it probes `gawk --help` once to filter that table to the options exposed by the local install,
- it computes safe unique long-option abbreviations from the discovered long options,
- and it adds context-aware value completion for source files, output-file options, lint values, load extensions, field separators, assignments, and trailing input files.

This is a single-command completer for `gawk` / `awk`, not a nested command-router.

## Registration and command names

The script registers the same native completer script block for:

- `gawk`
- `gawk.exe`
- `awk`
- `awk.exe`

Registration is done with:

```powershell
foreach ($commandName in @('gawk', 'gawk.exe', 'awk', 'awk.exe')) {
    Register-ArgumentCompleter -Native -CommandName $commandName -ScriptBlock { ... }
}
```

## How completion works

### 1. One-time catalog initialization

`Initialize-GawkCompletionCatalog` populates `$script:GawkCompletionCatalog` once per session.

It stores:

- the resolved executable path,
- the available option-definition table,
- short/long/canonical option maps,
- unique-prefix and minimal-abbreviation maps for long options,
- a prebuilt list of long-option suggestions,
- discovered load-extension names,
- lint values,
- field-separator hints,
- and assignment suggestion templates.

### 2. Help-validated option discovery

The script resolves the executable with `Get-GawkExecutablePath`, trying:

- the invoked command name,
- `gawk.exe`
- `gawk`
- `awk.exe`
- `awk`

If an executable is available, `Get-GawkHelpText` runs:

```powershell
gawk --help
```

`Get-GawkHelpOptionTokens` extracts short and long option tokens from that help text. The embedded static option table is then filtered so completion tracks the locally installed command surface more closely.

If help probing fails or returns nothing parseable, the completer falls back to the full embedded option table.

### 3. Safe long-option abbreviation handling

`Get-GawkUniqueLongPrefixMaps` computes all unique prefixes for the available long options.

That data is used in two ways:

- parsing accepts any long-option prefix that resolves uniquely to one real long option,
- option suggestions include the full long name and, conservatively, only the minimal unique abbreviation for that long option.

This lets the completer recognize safe GNU-style long-option abbreviations without flooding the menu with every possible prefix.

### 4. Parse-state tracking

`Update-GawkParseState` walks the already completed tokens and keeps a small state object:

- `EndOfOptions`
- `ProgramSourceProvided`
- `PendingSeparateOption`
- `AssignmentsAllowed`

That state is used to distinguish:

- option positions,
- option values that must come in the next token,
- the program-source position,
- trailing `name=value` assignments,
- and positional input-file arguments.

Important semantics handled by the parser:

- `--` stops option parsing,
- `-f`, `--file`, `-e`, `--source`, and `-E`, `--exec` count as providing program source,
- if no program source has been provided yet, the first non-option positional token is treated as the awk program source,
- after program source exists, trailing tokens can be assignments and/or input files,
- `-E` / `--exec` both provide program source and stop option parsing,
- `-E` / `--exec` also disable later assignment suggestions so trailing tokens are treated as input files only.

### 5. Value-aware completion

`Get-GawkValueCompletions` routes value-taking options by `ValueKind`:

- `SourceFile`
  - `-f`, `--file`
  - `-i`, `--include`
  - `-E`, `--exec`
  - completes filesystem paths, with `.awk`, `.gawk`, and `.inc` files sorted earlier
- `OutputFile`
  - `-d`, `--dump-variables`
  - `-D`, `--debug`
  - `-o`, `--pretty-print`
  - `-p`, `--profile`
  - completes filesystem paths for the optional attached or `--long=` file value forms
- `Lint`
  - `-L`, `--lint`
  - suggests `fatal`, `invalid`, and `no-ext`
- `LoadExtension`
  - `-l`, `--load`
  - suggests seeded extension names plus locally discovered extension-library names
- `FieldSeparator`
  - `-F`, `--field-separator`
  - suggests `,`, `:`, `;`, `|`, `\t`, and `[[:space:]]+`
- `Assignment`
  - `-v`, `--assign`
  - suggests `name=` and common awk variables such as `FS=`, `OFS=`, `RS=`, and `ORS=`

The completer also supports:

- attached short-value forms such as `-fscript.awk`, `-F,`, and `-lname`
- long `--option=value` forms when the option allows equals syntax

## Key completion behaviors / supported values

### Option completion

The completer suggests:

- `--` as an explicit end-of-options marker
- short options such as `-f`, `-F`, `-v`, `-e`, `-E`, `-i`, `-l`, `-L`, `-p`, `-o`, `-d`, and `-D`
- long options such as `--file`, `--field-separator`, `--assign`, `--source`, `--exec`, `--include`, `--load`, `--lint`, `--profile`, `--pretty-print`, `--dump-variables`, and the remaining help-validated gawk options
- minimal safe long-option abbreviations when a long option has a unique prefix

### Output-file option behavior

For `-d`, `-D`, `-o`, and `-p`, the optional file value is completed only in the forms the script models as valid:

- attached short forms such as `-pprofile.out`
- `--long=value` forms such as `--profile=profile.out`

Those options are intentionally not treated as taking a separate next-token value.

### Program-source vs trailing arguments

The script intentionally distinguishes the program-source slot from later positional arguments:

- before any program source exists, the first positional token is treated as awk program text or source and does not get file completion
- after program source has been provided explicitly or already consumed positionally, later tokens can complete as assignments and/or input files
- once assignment syntax is no longer allowed, positional completion falls back to input-file path completion only

### Local load-extension discovery

For `-l` / `--load`, the completer combines:

- a seeded list of common gawk extensions including `filefuncs`, `fnmatch`, `fork`, `inplace`, `intdiv`, `ordchr`, `readdir`, `readfile`, `revoutput`, `revtwoway`, `rwarray`, and `time`
- extension-library names discovered from `AWKLIBPATH`
- extension-library names discovered near the resolved gawk executable, including sibling `lib`, `gawk`, and `extensions` directories

Discovered files are limited to local library files with extensions such as `.dll`, `.so`, `.dylib`, and `.bundle`.

## Dependencies or external command expectations

The completer works best when a local `gawk` or `awk` executable is available on `PATH`.

If an executable is found:

- `--help` is used to validate which options are available locally
- nearby extension directories can be scanned for `--load` value suggestions

If no executable is found, the embedded metadata still provides static option and value completion, but help validation and install-local extension discovery are unavailable.

All completion data is local. The script does not make network calls.

## Usage / loading example

Dot-source the script:

```powershell
. .\gawk_completer.ps1
```

Example completion scenarios:

```powershell
gawk --<TAB>
gawk --file=.<TAB>
gawk -F <TAB>
gawk --lint=<TAB>
gawk --load <TAB>
gawk -v <TAB>
gawk -f .\script.awk FS=<TAB>
gawk -f .\script.awk .\in<TAB>
gawk -E .\script.awk .\in<TAB>
```

## Limitations / notes

- The completer is intentionally single-command and option-oriented; it does not implement a subcommand tree because gawk does not use one.
- Long-option abbreviation suggestions are conservative: the parser accepts any uniquely resolvable long prefix, but the menu only offers the minimal unique abbreviation plus the full long option.
- Before program source is known, the first positional token is treated as the awk program slot, so the completer intentionally avoids guessing file paths there.
- `--load` suggestions are local-only. They come from a seeded list plus libraries found in `AWKLIBPATH` and nearby install directories; the script does not search remote package sources or arbitrary system inventories.
- Help-based option filtering depends on the general shape of `gawk --help`. If that output changes significantly, the script falls back to the embedded definitions.

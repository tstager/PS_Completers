# sed completer

## What it completes / overview

`sed_completer.ps1` registers a standalone native PowerShell argument completer for GNU `sed`.

The script follows the repository's standalone completer pattern:

- it uses a script-scoped cache,
- it probes `sed --help` once to discover the locally available option tokens,
- it supplements that help-derived option set with the runtime-verified `--zero-terminated` alias for `-z`,
- and it adds value-aware behavior for script files, locales, line lengths, and positional input files.

## Registration and command names

The script registers a native completer for:

- `sed`
- `sed.exe`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'sed', 'sed.exe' -ScriptBlock { ... }
```

## How completion works

### 1. One-time catalog initialization

`Initialize-SedCompletionCatalog` populates `$script:SedCompletionCatalog` once per session.

It stores:

- the discovered `sed` executable path,
- option tokens parsed from `sed --help`,
- the resolved option-definition table used by the completer,
- line-length hint values,
- sample in-place backup suffix hints,
- and a lazily initialized locale cache for `--locale`.

### 2. Help-text discovery

The primary source for option tokens is:

```powershell
sed --help
```

`Get-SedHelpOptionTokens` extracts tokens such as:

- `-n`
- `--quiet`
- `--silent`
- `-e`
- `--expression`
- `-f`
- `--file`
- `-i`
- `--in-place`
- `--locale`
- `-l`
- `--line-length`
- `-E`
- `-r`
- `--regexp-extended`
- `-z`
- `--null-data`

If help probing fails, the script falls back to the embedded option metadata so completion still works.

`--zero-terminated` is intentionally added even though the local help output omits it, because runtime verification showed that alias is accepted by the installed build.

### 3. Parse-state tracking

The completer keeps a small parse state while walking completed tokens:

- `EndOfOptions`
- `PendingSeparateOption`
- `ExplicitScriptSource`
- `ImplicitScriptConsumed`

That state is used to decide whether the current token should be treated as:

- another option,
- an option value,
- the implicit sed script,
- or an input file.

### 4. Value-aware option routing

The completer has special handling for these value-taking options:

- `-e`, `--expression`
  - consumes a script value
  - offers a small set of starter sed-command hints such as `s///`, `p`, `d`, and `q`
  - avoids falling back to generic file completion for that slot
- `-f`, `--file`
  - completes filesystem paths, with `.sed` files sorted earlier when present
- `--locale`
  - completes cached .NET culture names
  - includes both hyphenated and underscored forms such as `en-US` and `en_US`
  - intentionally does **not** suggest `POSIX`
- `-l`, `--line-length`
  - offers a few small numeric hints
- `-i`, `--in-place`
  - treats bare forms as valid options
  - supports conservative attached/equals suffix completion hints such as `.bak` and `~`

### 5. Positional semantics

The script respects sed's implicit-script behavior:

- if no explicit `-e` or `-f` source has been provided, the first non-option positional token is treated as the sed script
- that implicit script slot does **not** get file completion
- after an explicit script source exists, later positional arguments complete as input files
- after the implicit script has been consumed, later positional arguments complete as input files
- `--` stops option completion, but the first post-`--` positional token is still treated as the implicit script when no explicit script source exists yet

## Key completion behaviors / supported values

### Option completion

The completer returns the currently available help-derived options, including:

- `-n`, `--quiet`, `--silent`
- `--debug`
- `-e`, `--expression`
- `-f`, `--file`
- `-i`, `--in-place`
- `-b`, `--binary`
- `-C`, `--ignore-locale`
- `--locale`
- `-l`, `--line-length`
- `--posix`
- `-E`, `-r`, `--regexp-extended`
- `-s`, `--separate`
- `--sandbox`
- `-u`, `--unbuffered`
- `-z`, `--null-data`, `--zero-terminated`
- `--help`
- `--version`

Option matching is case-sensitive so `-e`, `-E`, and `-C` remain distinct.

### `--option=value` forms

The completer routes these forms to value completion when appropriate:

- `--expression=...`
- `--file=...`
- `--locale=...`
- `--line-length=...`
- `--in-place=...`

### Short attached forms

The completer also handles conservative attached short forms for:

- `-eSCRIPT`
- `-fPATH`
- `-l80`

It intentionally avoids aggressive short-option cluster parsing because `sed` short clustering is nuanced and `-i` has optional attached suffix semantics. In-place suffix hints are primarily exposed through `--in-place=...`, with only conservative short-form handling in the script.

## Dependencies or external command expectations

This completer expects GNU `sed` to be installed if you want help-derived option discovery.

Preferred discovery source:

```powershell
sed --help
```

Locale completion uses .NET culture metadata from the current PowerShell runtime.

## Usage / loading example

Dot-source the script:

```powershell
. .\sed_completer.ps1
```

Example completion scenarios:

```powershell
sed --<TAB>
sed -f <TAB>
sed --file=.<TAB>
sed --locale <TAB>
sed --line-length=<TAB>
sed script.sed <TAB>
sed -e 's/x/y/' <TAB>
sed -- -n <TAB>
```

## Limitations / notes

- The completer does not try to fully synthesize sed-program text for `-e` or `--expression`; it only offers a few starter hints to avoid generic fallback completion.
- `-i` / `--in-place` suffix completion is intentionally conservative and limited to sample hints.
- Short-option clustering is not deeply interpreted beyond safe attached-value forms.
- Help parsing is used for option-token discovery, while value behavior is driven by embedded metadata.

# groff completer

## What it completes / overview

`groff_completer.ps1` registers a standalone native PowerShell argument completer for GNU `groff`.

The script follows the repository's standalone completer pattern:

- it uses a script-scoped lazy cache,
- it registers with `Register-ArgumentCompleter -Native`,
- it keeps a static option-definition table as the command grammar,
- it probes local `groff --help` once to keep the short-option surface aligned with the installed build,
- and it adds cached local discovery for output devices and macro packages.

This is a single-command completer for `groff` / `groff.exe`, not a subcommand router.

## Registration and command names

The script registers the same native completer for:

- `groff`
- `groff.exe`

Registration is done with:

```powershell
foreach ($commandName in @('groff', 'groff.exe')) {
    Register-ArgumentCompleter -Native -CommandName $commandName -ScriptBlock { ... }
}
```

## How completion works

### 1. One-time catalog initialization

`Initialize-GroffCompletionCatalog` populates `$script:GroffCompletionCatalog` once per session.

It stores:

- the resolved `groff` executable path,
- short-option tokens validated from local help output,
- the active option-definition table,
- short and long option maps,
- cached output-device names for `-T`,
- cached macro package names for `-m`,
- static warning-category values for `-w` / `-W`,
- and curated encoding hints for `-D` / `-K`.

### 2. Static grammar with local help validation

The authoritative grammar is embedded in `Get-GroffStaticOptionDefinitions`.

The completer models:

- flag-only switches such as `-a`, `-b`, `-c`, `-e`, `-g`, `-i`, `-j`, `-k`, `-l`, `-p`, `-R`, `-V`, `-X`, `-z`, and the other verified no-value switches,
- value-taking switches such as `-d`, `-f`, `-m`, `-n`, `-o`, `-r`, `-w`, `-D`, `-F`, `-I`, `-K`, `-L`, `-M`, `-P`, `-T`, and `-W`,
- and only the two valid long options: `--help` and `--version`.

`groff --help` is used to confirm which short switches are exposed locally so local-only switches such as `-J` can be preserved when present.

The script intentionally does **not** synthesize or suggest other GNU-style long options.

### 3. Attached and separate short-value parsing

`Parse-GroffShortToken` walks short-option tokens one character at a time.

It treats a token as a cluster until it reaches a value-taking short option, at which point the remainder of that token becomes the attached value.

Examples handled by the parser:

- `-Tutf8`
- `-mman`
- `-wspace`
- `-dfoo=bar`
- `-rS12`
- `-abTutf8`

If a value-taking option appears with no attached remainder, the parser marks the next token as that option's separate value. That supports forms such as:

- `-T utf8`
- `-m man`
- `-w space`
- `-d foo=bar`
- `-r S=12`

### 4. Value-aware completion

`Get-GroffValueCompletions` routes values by `ValueKind`.

- `-T`
  - completes cached local device names discovered from `font\dev*`
  - supplements discovery with static extras such as `xhtml`, `X75`, `X75-12`, `X100`, and `X100-12`
- `-m`
  - completes cached macro package names from `tmac` and `site-tmac`
  - normalizes `*.tmac` and `tmac.*` filenames to plain package names
- `-w` / `-W`
  - complete static warning categories such as `all`, `break`, `syntax`, `space`, `font`, and `file`
- `-D` / `-K`
  - complete curated encoding hints such as `utf8`, `latin1`, `latin2`, `latin5`, `latin9`, `koi8-r`, and `cp1047`
- `-F`, `-I`, `-M`
  - complete directory paths only
- `-d`, `-f`, `-n`, `-o`, `-r`, `-L`, `-P`
  - stay in value mode and return conservative placeholder-style suggestions instead of falling back to filesystem completion

That placeholder behavior is intentional. It keeps the completer side-effect free and avoids pretending to validate groff-specific expressions too aggressively.

### 5. Positional operands

Outside of option-value slots, the completer keeps normal operand completion available for `[file ...]`.

It offers:

- filesystem path completion for input files,
- and the literal `-` operand for standard input.

After `--`, completion switches fully to operand mode.

## Key completion behaviors / supported values

### Long-option surface

The completer suggests only:

- `--help`
- `--version`

No other `--long-option` forms are emitted.

### High-value completions

Representative examples:

- `groff -T<TAB>`
- `groff -T utf<TAB>`
- `groff -m<TAB>`
- `groff -m man<TAB>`
- `groff -w<TAB>`
- `groff -Wbr<TAB>`
- `groff -K<TAB>`
- `groff -D lat<TAB>`
- `groff -F .\<TAB>`

### Placeholder-style suppression

These slots intentionally avoid generic file completion:

- `groff -d<TAB>`
- `groff -dfoo=<TAB>`
- `groff -r<TAB>`
- `groff -P-pa4<TAB>`
- `groff -L-option<TAB>`
- `groff -o<TAB>`

## Dependencies or external command expectations

The completer works best when a local `groff` executable is available on `PATH`.

If `groff` is available:

- `groff --help` is used once to validate the short-option surface,
- install-local `share\groff\current\font\dev*` directories can be scanned for `-T` values,
- and install-local `tmac` / `site-tmac` directories can be scanned for `-m` values.

If local discovery is unavailable, the embedded grammar and static hint lists still provide completion.

All completion data is local. The script does not make network calls and does not invoke groff formatting pipelines.

## Usage / loading example

Dot-source the script:

```powershell
. .\groff_completer.ps1
```

Example completion scenarios:

```powershell
groff -<TAB>
groff --<TAB>
groff -T<TAB>
groff -T utf<TAB>
groff -m<TAB>
groff -m man<TAB>
groff -w<TAB>
groff -K<TAB>
groff -F .\<TAB>
groff -- -<TAB>
```

## Limitations / notes

- The completer intentionally keeps the long-option surface narrow: only `--help` and `--version` are suggested.
- `-d`, `-r`, `-o`, `-n`, `-L`, and `-P` use placeholder-style value handling rather than deep semantic validation.
- `-f` is kept value-aware enough to suppress path fallback, but it does not attempt to discover font-family names dynamically.
- Output-device and macro-package discovery is local-install-based and cached for the current session.

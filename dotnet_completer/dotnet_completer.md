# dotnet completer

## What it completes / overview

`dotnet_completer.ps1` registers a native PowerShell argument completer for `dotnet`.

It is a hybrid: a large vendored completion table generated from
`dotnet completions script pwsh`, with the installed SDK's own completion
engine, `dotnet complete`, layered in front of it. The live engine is what keeps
the surface aligned with the installed SDK; the vendored table supplies the
tooltips and every alias spelling, and remains the answer when the SDK cannot be
reached.

## Registration and command names

- Registers with: `Register-ArgumentCompleter -Native`
- Command name:
  - `dotnet`

Top-level command coverage in the script includes:

- `build`
- `build-server`
- `clean`
- `completions`
- `format`
- `fsi`
- `help`
- `msbuild`
- `new`
- `nuget`
- `pack`
- `package`
- `project`
- `publish`
- `reference`
- `restore`
- `run`
- `sdk`
- `solution`
- `store`
- `test`
- `tool`
- `vstest`
- `workload`

Nested command coverage includes, among others:

- `build-server shutdown`
- `completions script`
- `new create|details|install|list|search|uninstall|update`
- `nuget delete|locals|push|sign|trust|verify|why`
- `nuget trust author|certificate|list|remove|repository|source|sync`
- `package add|list|remove|search|update`
- `project convert`
- `reference add|list|remove`
- `sdk check`
- `solution add|list|migrate|remove`
- `tool execute|install|list|restore|run|search|uninstall|update`
- `workload clean|config|history|install|list|repair|restore|search|uninstall|update`
- `workload search version`

## How completion works

The script constructs a semicolon-delimited command path from bareword command elements, starting at `dotnet`.

Examples of internal routing keys:

- `dotnet`
- `dotnet;build`
- `dotnet;new;search`
- `dotnet;workload;search;version`

Path construction stops when it reaches a token that is:

- not a bare word
- an option/switch (starts with `-`)
- equal to the current word being completed

That key is then matched in a `switch` statement, which returns a static array of
`CompletionResult` objects for the matching context.

In parallel, `dotnet complete --position <n> "<command text>"` is asked about the
same slot. `$cursorPosition` is rebased by `$commandAst.Extent.StartOffset`, and
the extent is padded back out to the cursor when it sits after a trailing space -
without that padding the live engine is asked about the previous token instead of
the empty slot after it, and answers about the wrong thing.

The two sets are merged and then filtered, and this is where the vendored table's
shape matters. Each option spelling is its own row, with the canonical name in
`CompletionText` and the spelling in `ListItemText`:

```powershell
[CompletionResult]::new('--help', '--help', ...)
[CompletionResult]::new('--help', '-h',     ...)
```

Filtering `CompletionText` against the typed word therefore made every short and
alias form unreachable - `dotnet -h<TAB>` matched nothing - and made every alias
insert the same canonical text, so tab-cycling through six `--verbosity`
spellings inserted `--verbosity` six times. Matching and inserting
`ListItemText` fixes both: `-h` is reachable, and `-v`, `--v`, `/v` and
`--verbosity` are four distinct completions.

Matching is ordinal, and results are sorted by `ListItemText`.

### Value slots

When the settled token before the cursor is an option and every live suggestion
is a bare value, the slot is an option's value and the option list is not
repeated into it:

- `dotnet build --verbosity <TAB>` -> `q quiet m minimal n normal d detailed diag diagnostic`
- `dotnet build -c <TAB>` -> `Debug`, `Release`

Path-valued options (`-o`, `--output`, `--project`, `--file`, `--config`,
`--configfile`, `--package-directory`, `--artifacts-path`, `--tool-manifest`,
`--tool-path`, `--manifest`, `--solution`, ...) get file completion instead.

### Operand slots

A word that is not an option also gets project and solution completion:
`*.csproj`, `*.fsproj`, `*.vbproj`, `*.proj`, `*.sln`, `*.slnx`, `*.slnf`, and,
once a partial path has been typed, the directories to walk into.

## Key completion behaviors / supported values

- Provides static subcommand and switch completion for many `dotnet` command paths.
- Root suggestions include:
  - general CLI switches such as help, diagnostics, version, SDK/runtime listing
  - major top-level subcommands
- Nested command contexts expose command-specific switches and deeper subcommands.
- The completion data includes long-form options throughout the tree.
- Some entries are presented with alternate list text for aliases or short forms while still using a canonical completion entry internally.

## Dependencies or external command expectations

- Uses the installed SDK's `dotnet complete` when `dotnet` is on `PATH`.
- That child runs with standard input closed under a 2.5 second budget and is
  killed if it outlives it, and every answer is cached for the session, so a slow
  SDK cannot stall the prompt and no prefix is paid for twice. The previous
  revision spawned `dotnet complete` synchronously from five command arms with no
  cache, no timeout and no error handling.
- With no `dotnet` on `PATH` the completer still works from the vendored table
  alone.

## Usage / loading example

```powershell
. .\dotnet_completer.ps1
```

Example scenarios after loading:

```powershell
dotnet <Tab>
dotnet build --<Tab>
dotnet workload search <Tab>
```

## Runtime notes

- SDK version during this revision: `10.0.401`.
- Commands the vendored table never had - `dotnet sln`, `dotnet watch`,
  `dotnet package download` - now complete, because the live engine knows about
  them. They previously dead-ended into a directory listing.
- Template, workload and package-name values come from the live engine too, so
  `dotnet new <TAB>` lists the installed templates and `dotnet package add New<TAB>`
  searches NuGet. Those are the slots where the child can be slow; the timeout
  and the cache are what make that safe.

### Representative validation

Clean `pwsh -NoProfile` `TabExpansion2` runs:

- `dotnet -h` 0 -> `-h`
- `dotnet --` 8 -> 6 distinct spellings instead of duplicate `--help` rows
- `dotnet build --v` 7 identical `--verbosity` insertions -> `--v`,
  `--verbosity`, `--version-suffix`
- `dotnet build --verbosity ` 33 flags -> the 10 verbosity values
- `dotnet build --configuration ` and `dotnet build -c ` 33 flags -> `Debug`, `Release`
- `dotnet build -o ` 33 flags -> path completion
- `dotnet sln `, `dotnet package download ` filename fallback -> 9 and 15 real completions
- `dotnet watch ` filename fallback -> 36 commands and flags
- `dotnet new ` 21 -> 71, `dotnet package ` 7 -> 11 (gaining `download`)
- `dotnet build /v` -> `/v`, `/verbosity` instead of a stray `C:fcompat.dll`
- `$x = 1; dotnet bui` identical to the same input at the start of a line
- `$Error` did not grow across the probe set

## Limitations / notes

- The attached `--option=value` form is not split.
- Context detection only follows bareword subcommands and stops once an option or non-bareword token is encountered.

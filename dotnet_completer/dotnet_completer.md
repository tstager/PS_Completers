# dotnet completer

## What it completes / overview

`dotnet_completer.ps1` registers a native PowerShell argument completer for `dotnet`.

Unlike the help-driven completers in this repository, this script is a large static completion table. It does not invoke `dotnet` at completion time.

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

That key is then matched in a `switch` statement, which returns a static array of `CompletionResult` objects for the matching context. Results are finally filtered with:

```powershell
$_.CompletionText -like "$wordToComplete*"
```

and sorted by `ListItemText`.

## Key completion behaviors / supported values

- Provides static subcommand and switch completion for many `dotnet` command paths.
- Root suggestions include:
  - general CLI switches such as help, diagnostics, version, SDK/runtime listing
  - major top-level subcommands
- Nested command contexts expose command-specific switches and deeper subcommands.
- The completion data includes long-form options throughout the tree.
- Some entries are presented with alternate list text for aliases or short forms while still using a canonical completion entry internally.

## Dependencies or external command expectations

- No external command invocation is required by this completer.
- It only depends on loading the script into the PowerShell session.

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

## Limitations / notes

- The completion table is static, so it can drift from the installed `dotnet` version.
- It does not query the local SDK for dynamic values such as:
  - templates
  - workloads
  - package names
  - project paths
  - framework names
- Context detection only follows bareword subcommands and stops once an option or non-bareword token is encountered.

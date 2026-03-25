# bun completer

## What it completes / overview

`bun_completer.ps1` registers a native PowerShell argument completer for `bun` and `bun.exe`.

The implementation is a hybrid completer:

- it seeds a static Bun command tree, descriptions, aliases, and a small set of known option values,
- it resolves the local `bun` executable and parses `bun --help` / `bun <path> --help` output for commands, options, and possible values,
- and it augments that with local project data from the nearest `package.json`, workspace definitions, `node_modules`, `node_modules\.bin`, local `.bun-create` folders, and the filesystem.

All completion data is collected locally. The script does not query package registries or make network calls.

## Registration and command names

The script registers one native completer for:

- `bun`
- `bun.exe`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName 'bun', 'bun.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Bun -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

## How completion works

### 1. Script-scoped cache

`$script:BunCompletionCache` stores:

- the resolved `bun` executable path,
- parsed help data by command path,
- cached `package.json` content by file path,
- cached workspace names by project root,
- cached `node_modules` package names by root,
- cached local create-template names by current root,
- a static command tree and descriptions,
- alias maps,
- and a small table of static option values.

Workspace names and `node_modules` package names use short TTL-based caches, and local create templates use a slightly longer TTL cache.

### 2. Executable discovery and help capture

`Get-BunExecutablePath` probes `bun.exe` and `bun` with `Get-Command`.

When an executable is available, `Invoke-BunCapture` runs local help commands such as:

```powershell
bun --help
bun run --help
bun pm pkg --help
```

and captures the returned text for parsing.

### 3. Command-context parsing

`Get-BunCommandContext` walks the tokens already entered on the command line and tracks:

- the active subcommand path,
- consumed positional arguments,
- whether the previous option is waiting for a value,
- whether parsing has passed `--`,
- and whether the cursor is completing an empty trailing argument.

Subcommands are matched with `Find-BunSubcommand`, which combines help-discovered commands with static alias maps such as:

- root aliases: `i` → `install`, `a` → `add`, `r` / `rm` → `remove`, `c` → `create`
- `bun pm list` → `bun pm ls`

### 4. Help-driven command, option, and value parsing

`Get-BunParsedHelpData` reads Bun help sections and extracts:

- subcommands from `Commands:` sections,
- options from `Flags:` or `Options:` sections,
- which options appear to expect a value,
- and simple possible-value hints from quoted values or phrases such as `possible values:`.

`Get-BunHelpData` merges that parsed help with the script's static command tree, so the completer can combine repository-defined fallbacks with the locally installed Bun CLI surface.

### 5. Local metadata and filesystem completion

The script supplements help output with project-local data:

- `Get-BunScriptNames` reads script names from the nearest `package.json`
- `Get-BunWorkspaceNames` resolves workspace names from `workspaces`
- `Get-BunPackagePropertyPaths` expands package property paths from the nearest `package.json`
- `Get-BunInstalledPackageNames` enumerates packages from the nearest `node_modules`
- `Get-BunNodeModulesBinNames` enumerates local binaries from `node_modules\.bin`
- `Get-BunCreateTemplateNames` reads template folder names from `$HOME\.bun-create` and `.\.bun-create`
- `Get-BunPathSuggestions` provides file and directory completion, preserves quotes, and prefers selected file extensions for some argument positions

### 6. Result shaping

`Complete-Bun` chooses among:

- `--option=value` completion,
- separate next-token option value completion,
- subcommand suggestions,
- positional suggestions,
- and option-name suggestions.

Results are deduplicated and filtered by prefix before being returned as `System.Management.Automation.CompletionResult` objects.

## Key completion behaviors / supported values

### Static root command tree

The script seeds these top-level Bun commands:

- `run`
- `test`
- `x`
- `repl`
- `exec`
- `install`
- `add`
- `remove`
- `update`
- `audit`
- `outdated`
- `link`
- `unlink`
- `publish`
- `patch`
- `pm`
- `info`
- `why`
- `list`
- `build`
- `init`
- `create`
- `upgrade`
- `feedback`

It also seeds important nested paths:

- `pm` → `scan`, `pack`, `bin`, `ls`, `why`, `whoami`, `view`, `version`, `pkg`, `hash`, `hash-string`, `hash-print`, `cache`, `migrate`, `untrusted`, `trust`, `default-trusted`
- `pm cache` → `rm`
- `pm pkg` → `get`, `set`, `delete`, `fix`

### Help-driven option completion

Option names are primarily discovered from the local Bun help text for the active command path.

The script also keeps a static list of options that are known to expect values for important paths, including:

- root runtime options such as `--preload`, `--require`, `--import`, `--eval`, `--cwd`, `--env-file`, and `--config`
- `run` options such as `--shell`, `--main-fields`, `--extension-order`, `--loader`, and `--jsx-runtime`
- `build` options such as `--target`, `--outdir`, `--outfile`, `--sourcemap`, `--format`, `--packages`, and `--env`
- `test` options such as `--timeout`, `--coverage-reporter`, `--reporter`, and `--reporter-outfile`
- package-manager options such as `publish --access`, `publish --tag`, `patch --patches-dir`, `outdated --filter`, `x --package`, `pm pack --destination`, and `pm version --preid`

### Static value hints included in the script

The script explicitly seeds these option values:

- `--install` → `auto`, `fallback`, `force`
- `--dns-result-order` → `verbatim`, `ipv4first`, `ipv6first`
- `--unhandled-rejections` → `strict`, `throw`, `warn`, `none`, `warn-with-error-code`
- `--backend` → `clonefile`, `hardlink`, `symlink`, `copyfile`
- `--omit` → `dev`, `optional`, `peer`
- `--linker` → `isolated`, `hoisted`
- `--audit-level` → `low`, `moderate`, `high`, `critical`
- `run --shell` → `bun`, `system`
- `build --target` → `browser`, `bun`, `node`
- `build --sourcemap` → `linked`, `inline`, `external`, `none`
- `build --format` → `esm`, `cjs`, `iife`
- `build --packages` → `external`, `bundle`
- `build --jsx-runtime` → `automatic`, `classic`
- `build --env` → `disable`
- `test --coverage-reporter` → `text`, `lcov`
- `test --reporter` → `junit`, `dots`
- `publish --access` → `public`, `restricted`
- `pm pack --gzip-level` → `0` through `9`
- `init --react` → `tailwind`, `shadcn`

Those static hints are merged with any values discovered from Bun help output.

### Workspace, package, and property-path value completion

The script adds several project-local value sources:

- `bun run --filter <TAB>` and `bun run -f <TAB>` suggest workspace names
- `bun update --filter <TAB>` suggests workspace names
- `bun outdated --filter <TAB>` and `bun outdated -F <TAB>` suggest workspace names
- `bun remove <TAB>`, `bun update <TAB>`, `bun info <TAB>`, `bun why <TAB>`, `bun patch <TAB>`, `bun outdated <TAB>`, `bun x <TAB>`, `bun pm view <TAB>`, and `bun pm trust <TAB>` suggest package names from the local manifest and/or `node_modules`
- `bun info <package> <TAB>`, `bun why <package> <TAB>`, `bun pm pkg get <TAB>`, and `bun pm pkg delete <TAB>` suggest package.json property paths
- `bun pm pkg set <TAB>` suggests `property=` assignments
- `bun pm version <TAB>` suggests `patch`, `minor`, `major`, `prepatch`, `preminor`, `premajor`, `prerelease`, and `from-git`

`Get-BunPackagePropertyPaths` recursively expands object properties from the nearest `package.json`, includes `[]` and indexed array forms, limits recursion depth to four levels, and only inspects the first three items of each array.

### Positional and path-aware completion

The script adds positional suggestions for several commands:

- bare `bun <TAB>` suggests top-level commands, local `package.json` script names, and source-like files
- `bun run <TAB>` suggests script names, `node_modules\.bin` binaries, and source-like files
- `bun build <TAB>` and `bun test <TAB>` suggest source-like files
- `bun init <TAB>` suggests directories
- `bun create <TAB>` suggests local `.bun-create` template names and `.jsx` / `.tsx` entries for the first positional argument, then directories for the second positional argument
- `bun publish <TAB>` suggests `.tgz` / `.tar.gz` tarball paths

For path-valued options, the completer returns filesystem suggestions and prefers relevant extensions for some arguments, for example:

- `--config` / `-c` → `.toml`
- `--env-file` → `.env`
- `--preload`, `-r`, `--require`, `--import` → JavaScript / TypeScript source extensions
- `--tsconfig-override` → `.json`
- `--reporter-outfile` → `.xml`
- `--windows-icon` → `.ico`
- `--filename` → `.tgz`

Directory-only completion is used for options such as `--cwd`, `--outdir`, `--coverage-dir`, `--destination`, `--cache-dir`, and `--patches-dir`.

The completer supports both separate values and `--option=value` forms. When completing paths, it preserves or adds quotes when needed and appends a trailing directory separator for directories.

## Dependencies or external command expectations

This completer works best when `bun.exe` or `bun` is available on `PATH`.

When Bun is available:

- help parsing can discover command-path-specific options and subcommands from the installed version
- help text can contribute additional option values beyond the static table

When Bun is not available, the script can still return static command-tree suggestions, alias handling, local `package.json` data, local `node_modules` data, local `.bun-create` templates, and filesystem-based suggestions. The help-driven parts are simply unavailable.

Project-local completion depends on the current working directory:

- the nearest parent `package.json` is used for scripts, property paths, workspaces, and manifest package names
- the nearest parent `node_modules` is used for installed-package and `.bin` suggestions

All discovery is local-only.

## Usage / loading example

Dot-source the script:

```powershell
. .\bun_completer.ps1
```

Example completion scenarios:

```powershell
bun <TAB>
bun run <TAB>
bun run --filter <TAB>
bun build --outfile=<TAB>
bun test --coverage-reporter <TAB>
bun create <TAB>
bun pm pkg set <TAB>
```

## Limitations / notes

- The help parser depends on the general shape of Bun help output, especially `Commands:` and `Flags:` / `Options:` sections. Major formatting changes could reduce dynamic completion quality.
- The script only adds static value hints for the options listed above. Other option values are available only if Bun's help text exposes them or if the script has special local logic for that position.
- Package and workspace suggestions are local-only. The completer does not query remote registries or discover packages outside the nearest local manifest and `node_modules`.
- After `--`, the parser stops offering Bun-specific option and positional suggestions.
- Command-path parsing is intentionally simple: once a non-option positional argument is consumed for a branch, later non-option tokens are treated as positional values rather than additional subcommands.

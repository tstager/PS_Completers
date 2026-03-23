# npm completer

## What it completes / overview

`npm_completer.ps1` registers a PowerShell argument completer for npm command invocations.

The script uses a hybrid design:

- it seeds a static command tree for common npm commands and nested verbs,
- it parses `npm [path] --help` output for options, subcommands, and some option values,
- and it augments that with local project metadata from nearby `package.json`, workspaces, and `node_modules`.

All completion metadata is collected locally. The script does not query the npm registry or make network calls.

## Registration and command names

The script registers the same completer script block for:

- native completion targets from `Get-NpmCommandPathTargets`
  - always `npm`
  - always `npm.cmd`
  - `npm.exe` when it is available through `Get-Command`
- PowerShell command names
  - `npm`
  - `npm.ps1`

Registration is done with:

```powershell
Register-ArgumentCompleter -Native -CommandName (Get-NpmCommandPathTargets) -ScriptBlock $NpmNativeCompleter
Register-ArgumentCompleter -CommandName @('npm', 'npm.ps1') -ScriptBlock $NpmNativeCompleter
```

## How completion works

### 1. Script-scoped cache

`$script:NpmCompletionCache` stores:

- the resolved npm executable path,
- parsed help data by command path,
- cached `package.json` data,
- cached workspace names,
- cached installed package names from `node_modules`,
- cached config keys from `npm config ls -l`,
- static command, option-value, and positional-value tables.

The script uses short TTL-based caches for workspace names, installed package names, and config keys so repeat completion calls do not recalculate everything every time.

### 2. Executable discovery and command capture

`Get-NpmExecutablePath` resolves `npm.cmd`, `npm`, or `npm.exe`. If npm cannot be found, the completer returns no suggestions.

`Invoke-NpmCommandCapture` runs local npm commands and captures text output. When the resolved command is a `.cmd` wrapper, it invokes it through `cmd.exe`; otherwise it starts the executable directly.

### 3. Command-path parsing

`Get-NpmCommandState` walks the tokens already entered on the command line and tracks:

- the active subcommand path,
- positional arguments already consumed,
- whether an option is waiting for a value,
- and whether completion is past `--`.

Command-path parsing resolves known aliases to their canonical npm command paths before it asks for nested subcommands, options, or values. That means alias forms such as `npm c`, `npm dist-tags`, `npm author`, `npm ogr`, `npm i`, and `npm x` follow the same completion branches as `config`, `dist-tag`, `owner`, `org`, `install`, and `exec`.

That state is then used to decide whether to suggest subcommands, options, option values, or positional values.

### 4. Help-driven completion

`Get-NpmHelpData` calls:

```powershell
npm [path] --help
```

and parses the resulting help text to discover:

- subcommands,
- options,
- and value hints exposed in help output.

This lets the completer stay closer to the installed npm version than a purely hard-coded table.

### 5. Local metadata completion

The script supplements help parsing with project-local data:

- `Get-NpmScriptNames` reads script names from the nearest `package.json`
- `Get-NpmWorkspaceNames` resolves workspaces from the nearest `package.json`
- `Get-NpmPackagePropertyPaths` builds package property paths for `npm pkg ...`
- `Get-NpmInstalledPackageNames` enumerates packages from the nearest `node_modules`
- `Get-NpmConfigKeys` parses config keys from local `npm config ls -l` output

## Key completion behaviors / supported values

### Static root commands

The script seeds these top-level npm commands:

- `access`
- `adduser`
- `audit`
- `bugs`
- `cache`
- `ci`
- `completion`
- `config`
- `dedupe`
- `deprecate`
- `diff`
- `dist-tag`
- `docs`
- `doctor`
- `edit`
- `exec`
- `explain`
- `explore`
- `find-dupes`
- `fund`
- `get`
- `help`
- `help-search`
- `init`
- `install`
- `install-ci-test`
- `install-test`
- `link`
- `ll`
- `login`
- `logout`
- `ls`
- `org`
- `outdated`
- `owner`
- `pack`
- `ping`
- `pkg`
- `prefix`
- `profile`
- `prune`
- `publish`
- `query`
- `rebuild`
- `repo`
- `restart`
- `root`
- `run`
- `sbom`
- `search`
- `set`
- `shrinkwrap`
- `star`
- `stars`
- `start`
- `stop`
- `team`
- `test`
- `token`
- `trust`
- `undeprecate`
- `uninstall`
- `unpublish`
- `unstar`
- `update`
- `version`
- `view`
- `whoami`

### Important nested verbs

The script explicitly seeds these nested command paths:

- `config` → `set`, `get`, `delete`, `list`, `edit`, `fix`
- `pkg` → `set`, `get`, `delete`, `fix`
- `cache` → `add`, `clean`, `ls`, `verify`, `npx`
- `cache npx` → `ls`, `rm`, `info`
- `team` → `create`, `destroy`, `add`, `rm`, `ls`
- `owner` → `add`, `rm`, `ls`
- `access` → `list`, `get`, `set`, `grant`, `revoke`
- `access list` → `packages`, `collaborators`
- `access get` → `status`
- `org` → `set`, `rm`, `ls`
- `profile` → `enable-2fa`, `disable-2fa`, `get`, `set`
- `dist-tag` → `add`, `rm`, `ls`

### Helpful local value completions

The completer adds several useful local-only value sources:

- `npm run <TAB>` suggests script names from the nearest `package.json`
- `--workspace` and `-w` suggest workspace names resolved from local workspaces
- `npm config get|set|delete <TAB>` suggests config keys from `npm config ls -l`
- `npm config set <TAB>` suggests `key=` forms
- `npm pkg get|set|delete <TAB>` suggests package property paths from the nearest `package.json`
- `npm pkg set <TAB>` suggests `path=` forms
- `install`, `uninstall`, `update`, `outdated`, `ls`, and `explain` suggest installed package names from local `node_modules`
- `owner ...` and `dist-tag ...` also use local installed package names in the positions the script recognizes

The script also supports `--option=value` completion. If the current token looks like `--name=...`, it completes values and returns suggestions in the same `--name=value` form.

For npm config, the completer keeps lowercase `-l` distinct from uppercase `-L`: `npm config ls -l` remains the long-listing form used to discover local config keys, while `--location` and `-L` complete the supported location values `global`, `user`, and `project`.

### Static value hints included in the script

The script seeds several option and positional value hints, including:

- `--location` / `config --location` → `global`, `user`, `project`
- `install --install-strategy` → `hoisted`, `nested`, `shallow`, `linked`
- `install --omit` → `dev`, `optional`, `peer`
- `install --include` → `prod`, `dev`, `optional`, `peer`
- `install --allow-git` → `all`, `none`, `root`
- `publish --access` → `restricted`, `public`
- `search --color` → `always`
- `access set`, `access grant`, `profile enable-2fa`, and `org set` positional hints for selected known values

## Dependencies or external command expectations

This completer expects npm to be available on `PATH` as one of:

- `npm`
- `npm.cmd`
- optionally `npm.exe`

Project-aware completion works best when you run it inside a package directory with a nearby `package.json`. Some value completions also depend on local `node_modules` or workspaces existing on disk.

## Usage / loading example

Dot-source the script in your PowerShell session or profile:

```powershell
. .\npm_completer.ps1
```

Example completion scenarios:

```powershell
npm <TAB>
npm config <TAB>
npm config set <TAB>
npm pkg get <TAB>
npm run <TAB>
npm install --omit=<TAB>
npm install --workspace <TAB>
```

## Limitations / notes

- Help-based completion depends on the general shape of `npm --help` output. Significant help-format changes can reduce completion quality.
- The static command tree is intentionally selective; the script merges static data with parsed help instead of hard-coding every npm branch by hand.
- Package name suggestions come from local `node_modules`, not from the registry.
- `npm pkg` property-path suggestions only recurse four levels deep and only sample the first few array entries.
- Workspace, installed-package, and config-key suggestions reflect local filesystem and local npm command output, so they may be empty outside a project or before dependencies are installed.
- After `--`, the completer stops offering the positional suggestions handled by the script.

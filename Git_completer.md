# Git completer

## What it completes / overview
`Git_completer.ps1` registers a native argument completer for `git`. The script is self-contained and builds completions from the installed Git CLI plus a small amount of repository-local fallback data.

It covers top-level subcommands, nested subcommands, flags discovered from `git -h` output, and several value completions such as refs, remotes, worktree paths, tracked/untracked files, hook names, and selected `git init` option values.

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command name: `git`
- Entry point: `$GitNativeCompleter`

```powershell
Register-ArgumentCompleter -Native -CommandName git -ScriptBlock $GitNativeCompleter
```

If `git` is not available in `PATH`, the completer returns without emitting suggestions.

## How completion works
The completer tokenizes the current command line with a simple non-whitespace regex and then computes an argument index based on whether the cursor is after a trailing space.

Internal helper scriptblocks handle distinct parts of the workflow:
- `$newResult` creates `CompletionResult` instances.
- `$completeList` emits sorted unique matches using the current `$wordToComplete` prefix.
- `$completeOrderedList` preserves preferred ordering while still deduplicating.
- `$completeFileSystemPaths` delegates to PowerShell filename completion and can restrict results to directories.
- `$getRefs`, `$getRemotes`, `$getFiles`, and `$getWorktreePaths` call Git for dynamic data.

### Metadata discovery and caching
The script stores parsed help metadata in `$global:GitHelpMetadataCache`.
- `'<root>'` stores top-level subcommands plus global flags.
- Other keys are space-separated command paths such as `remote` or `hook run`.

For non-root commands, `$getCommandMetadata` runs `git <command path> -h`, parses:
- flags from help text with regex
- nested subcommands from `usage:` / `or:` lines

A hardcoded `$documentedNestedSubcommands` map supplements help parsing for command groups whose help output does not fully expose their subcommands.

### Command-path detection
`$getCommandContext` walks non-flag arguments from left to right. Whenever a token matches one of the current command metadata object's known subcommands, it extends the command path and refreshes metadata for the deeper path.

`$getArgumentsAfterPath` and `$getPositionalArgumentsAfterPath` then isolate arguments that come after the recognized command path so later logic can make subcommand-specific decisions.

## Key completion behaviors / supported values
### Top-level suggestions
At the top level, the script:
- suggests global Git flags when the current word starts with `-`
- otherwise suggests top-level subcommands

It prefers this display order when those subcommands exist in the installed Git:
- `status`
- `add`
- `commit`
- `push`
- `pull`
- `fetch`
- `hook`
- `switch`
- `checkout`
- `branch`
- `merge`
- `rebase`
- `log`
- `diff`
- `stash`
- `tag`
- `restore`
- `reset`
- `rm`

Remaining discovered subcommands are appended alphabetically.

### Global flags
The root metadata includes these global flags:
- `--help`
- `--version`
- `--exec-path`
- `--html-path`
- `--man-path`
- `--info-path`
- `--paginate`
- `--git-dir`
- `--work-tree`
- `--namespace`
- `-C`
- `-c`
- `-p`
- `--no-pager`

### Nested subcommand families
The script explicitly documents nested subcommands for these command groups:
- `hook`
- `maintenance`
- `notes`
- `reflog`
- `remote`
- `sparse-checkout`
- `stash`
- `submodule`
- `worktree`

Examples from the built-in nested map include:
- `hook run`
- `remote add|get-url|prune|remove|rename|rm|set-branches|set-head|set-url|show|update`
- `stash apply|branch|clear|create|drop|export|import|list|pop|push|save|show|store`
- `worktree add|list|lock|move|prune|remove|repair|unlock`

### Context-aware value completions
- `git config ...` completes a fixed list of common config keys such as `user.name`, `user.email`, `core.editor`, `init.defaultBranch`, `pull.rebase`, and several alias examples.
- `git hook run ...` completes hook names from a default hook list plus files found under `git rev-parse --git-path hooks` (excluding `*.sample`).
- `git remote remove`, `rename`, `show`, `prune`, `update`, `get-url`, `set-head`, `set-branches`, and `set-url` complete remote names from `git remote`.
- `git remote set-head` and `git remote set-branches` also complete refs once the remote argument has been supplied.
- `git worktree add` completes refs after the first positional argument.
- `git worktree lock`, `move`, `remove`, `repair`, and `unlock` complete worktree paths from `git worktree list --porcelain`.
- `git checkout` / `git switch` complete refs by default.
- `git checkout -b|-B` and `git switch -c|-C` switch to new-branch-name suggestions such as `feature/`, `bugfix/`, `hotfix/`, `chore/`, `docs/`, `refactor/`, `test/`, plus `<current-branch>-fix` and `<current-branch>-update` when the current branch can be resolved.
- `git merge`, `rebase`, `reset`, `show`, `log`, `diff`, `cherry-pick`, and `revert` complete refs.
- `git push`, `pull`, and `fetch` complete remotes.
- `git add`, `restore`, `rm`, and `mv` complete tracked and untracked file paths from `git ls-files`.

### `git init` special handling
`init` gets additional option-value support beyond general help parsing.

Preferred flag suggestions include:
- `--quiet`
- `-q`
- `--bare`
- `--template=`
- `--separate-git-dir`
- `--object-format=`
- `--ref-format=`
- `-b`
- `--initial-branch=`
- `--shared`
- `--shared=`

Supported value completions:
- `--template` and `--separate-git-dir`: directory paths
- `--object-format`: `sha1`, `sha256`
- `--ref-format`: `files`, `reftable`
- `-b` / `--initial-branch`: configured `init.defaultBranch` plus `main`, `master`, `develop`, `trunk`
- `--shared`: `false`, `true`, `umask`, `group`, `all`, `world`, `everybody`, `0640`, `0660`, `0770`

The script handles both separated and attached forms such as `--object-format=sha256`.

## Dependencies or external command expectations
The completer expects a working `git` executable in `PATH`.

It shells out to Git for completion data, including:
- `git --list-cmds=main,others,alias,nohelpers`
- `git <command path> -h`
- `git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags`
- `git rev-parse --short HEAD`
- `git remote`
- `git ls-files`
- `git ls-files --others --exclude-standard`
- `git worktree list --porcelain`
- `git symbolic-ref --short HEAD`
- `git rev-parse --git-path hooks`
- `git config --get init.defaultBranch`

Because the completer uses live Git output, results depend on the installed Git version and the current repository context.

## Usage / loading example
```powershell
. "$PSScriptRoot\Git_completer.ps1"

# Example completions
# git <TAB>
# git remote <TAB>
# git checkout <TAB>
# git init --object-format=<TAB>
```

## Limitations / notes
- Tokenization uses `\S+`, so it is simpler than PowerShell's full parser and is oriented toward native-command argument shapes.
- Help metadata is cached in a global variable for the session and is not invalidated automatically.
- Nested subcommand coverage partly depends on parsing `git -h` output and partly on the hardcoded `$documentedNestedSubcommands` map.
- `git config` key completion is a fixed curated list in this script, not a live read of repository or global config keys.
- New-branch completion for `checkout` / `switch` uses naming suggestions rather than enumerating existing branches.
- When a command path is treated as a leaf command and the cursor is at a trailing-space boundary with no positional arguments, the completer can fall back to that command's flag set.
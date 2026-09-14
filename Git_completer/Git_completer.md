# Git completer

## What it completes / overview
`Git_completer.ps1` registers a native argument completer for `git`. The script is self-contained and builds completions from the installed Git CLI plus a small amount of repository-local fallback data.

It covers top-level subcommands, nested subcommands, flags discovered from `git -h` output, and several value completions such as refs, remotes, worktree paths, tracked/untracked files, hook names, and selected `git init` option values.

## Registration and command names
- Registers with `Register-ArgumentCompleter -Native`
- Command names: `git`, `git.exe`
- Entry point: `Complete-GitNative`

```powershell
Register-ArgumentCompleter -Native -CommandName @('git', 'git.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-GitNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}
```

The registration call stays at script scope with literal arguments because the CompleterActions strict import grammar requires it; all logic lives in `Complete-GitNative` and its helpers.

If `git` is not available in `PATH`, the completer returns without emitting suggestions.

## How completion works
The completer tokenizes the current command line with a simple non-whitespace regex, keeps only the tokens that start before the cursor (after rebasing `$cursorPosition` by `$commandAst.Extent.StartOffset`), and then computes an argument index based on whether the cursor is after a trailing space. Because the token list is cut at the cursor, completing a word in the middle of a line works the same as completing at the end.

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
- the argument each option takes, read from the option column of its help row (`-F, --[no-]file <file>` yields the spec `<file>` for both `-F` and `--file`)
- nested subcommands from `usage:` / `or:` lines

A user alias is **never** passed to `git ... -h`. git has no help to print for a shell alias (`!cmd ...`) and would run the alias body instead, so the alias table is read once per session with `git config --get-regexp "^alias."`; an alias that expands to a git command reuses that command's metadata, and a shell alias gets an empty metadata object.

git deliberately prints an abbreviated `-h` for its revision-walking commands, so `log`, `show`, `diff`, and `whatchanged` are supplemented from the `git-completion.bash` that ships beside the installed git (`<git>\mingw64\share\git\completion\git-completion.bash`). Its `__git_*` option variables and the option tokens inside the matching completion function are parsed once and cached, which is where `--oneline`, `--graph`, `--stat`, and `--pretty` come from. The same file supplies the value lists for `--pretty`, `--format`, `--date`, `--diff-algorithm`, `--submodule`, `--ws-error-highlight`, `--color-moved`, `--color-moved-ws`, and `--diff-merges`.

A hardcoded `$documentedNestedSubcommands` map supplements help parsing for command groups whose help output does not fully expose their subcommands.

### Command-path detection
`$getCommandContext` walks non-flag arguments from left to right. Whenever a token matches one of the current command metadata object's known subcommands, it extends the command path and refreshes metadata for the deeper path. A global option that takes a value (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, `--exec-path`, `--config-env`) consumes the token after it, so that value is never mistaken for the subcommand; `-C`, `--git-dir`, and `--work-tree` complete directories in their value slot.

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
- `git config ...` offers modern `config` subcommands plus a fixed list of common config keys such as `user.name`, `user.email`, `core.editor`, `init.defaultBranch`, `pull.rebase`, and several alias examples at the first argument slot. `git config get|set|unset ...` continue key completion in the key slot, and `git config --file` / `git config --file=` complete file paths.
- `git hook run ...` completes hook names from a default hook list plus files found under `git rev-parse --git-path hooks` (excluding `*.sample`).
- `git remote remove`, `rename`, `show`, `prune`, `update`, `get-url`, `set-head`, `set-branches`, and `set-url` complete remote names from `git remote`.
- `git remote set-head` and `git remote set-branches` also complete refs once the remote argument has been supplied.
- `git worktree add` completes refs after the first positional argument.
- `git worktree lock`, `move`, `remove`, `repair`, and `unlock` complete worktree paths from `git worktree list --porcelain`.
- `git checkout` / `git switch` complete refs by default.
- `git checkout -b|-B` and `git switch -c|-C` switch to new-branch-name suggestions such as `feature/`, `bugfix/`, `hotfix/`, `chore/`, `docs/`, `refactor/`, `test/`, plus `<current-branch>-fix` and `<current-branch>-update` when the current branch can be resolved. After the new branch name has been supplied, completion returns to refs for the optional start point.
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

Option values are driven by the argument spec captured from help: `<file>` / `<path>` / `<dir>` complete file system paths, `<commit>` / `<ref>` / `<branch>` and their relatives complete refs, and a parenthesised alternation such as `(direct|inherit)` completes its members. An option whose spec names none of those completes nothing, which leaves the slot to PowerShell's own filename fallback rather than dumping the command's flag list into it. An attached `--option=<path>` result is quoted as a whole token, so a path containing a space stays syntactically valid.

`git help <TAB>` offers the command list plus the concept guides from `git --list-cmds=list-guide`.

## Dependencies or external command expectations
The completer expects a working `git` executable in `PATH`.

It shells out to Git for completion data, including:
- `git --list-cmds=main,others,alias,nohelpers`
- `git --list-cmds=list-guide`
- `git config --get-regexp "^alias."`
- `git <command path> -h` (never for a user alias)
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
- `rev-parse` still gets only what its abbreviated `-h` prints; `git-completion.bash` has no completion function for it to supplement from.
- A shell alias (`!cmd ...`) gets no flag or subcommand completion at all, because reading its surface would mean running it.
- `git config` key completion is a fixed curated list in this script, not a live read of repository or global config keys.
- New-branch completion for `checkout` / `switch` uses naming suggestions rather than enumerating existing branches.
- When a command path is treated as a leaf command and the cursor is at a trailing-space boundary with no positional arguments, the completer can fall back to that command's flag set.

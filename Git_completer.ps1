# Git Native Argument Completer for PowerShell
# Provides intelligent tab completion for git commands, subcommands, and flags.
# This implementation uses git's own capabilities to fetch relevant completions,
# ensuring that it stays up-to-date with the installed version of git.
   
$GitNativeCompleter = {
    param($wordToComplete, $commandAst, $cursorPosition)

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return
    }

    $line = $commandAst.ToString()
    $tokens = @([regex]::Matches($line, '\S+') | ForEach-Object { $_.Value })

    if ($tokens.Count -eq 0) {
        return
    }

    $hasTrailingSpace = ($line -match '\s$') -or ($cursorPosition -gt $line.Length)
    if ($hasTrailingSpace) {
        $argIndex = $tokens.Count - 1
    }
    else {
        $argIndex = $tokens.Count - 2
    }

    if ($argIndex -lt 0) {
        $argIndex = 0
    }

    $newResult = {
        param($value)
        [System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $value)
    }

    $completeList = {
        param([string[]]$values)
        $values |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { & $newResult $_ }
    }

    $getRefs = {
        @(
            git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>$null
            git rev-parse --short HEAD 2>$null
        ) | Where-Object { $_ }
    }

    $getRemotes = {
        @(git remote 2>$null)
    }

    $getFiles = {
        @(
            git ls-files 2>$null
            git ls-files --others --exclude-standard 2>$null
        ) | Where-Object { $_ }
    }

    $globalGitFlags = @(
        '--help',
        '--version',
        '--exec-path',
        '--html-path',
        '--man-path',
        '--info-path',
        '--paginate',
        '--git-dir',
        '--work-tree',
        '--namespace',
        '-C',
        '-c',
        '-p',
        '--no-pager'
    )

    $subcommandFlags = @{
        'add'      = @('--all', '-A', '--patch', '-p', '--interactive', '-i', '--update', '-u', '--intent-to-add', '-N')
        'branch'   = @('--all', '-a', '--delete', '-d', '-D', '--move', '-m', '-M', '--list', '-l', '--set-upstream-to')
        'checkout' = @('--detach', '-b', '-B', '--track', '-t', '--orphan', '--patch', '-p')
        'switch'   = @('--detach', '-c', '-C', '--track', '--guess', '--discard-changes', '--force', '-f')
        'commit'   = @('--all', '-a', '--amend', '--message', '-m', '--patch', '-p', '--reuse-message', '-C', '--fixup', '--squash', '--signoff', '-s')
        'config'   = @('--global', '--system', '--local', '--worktree', '--unset', '--unset-all', '--add', '--replace-all', '--get', '--get-all', '--list', '-l', '--type')
        'diff'     = @('--cached', '--staged', '--name-only', '--name-status', '--stat', '--color', '--no-color', '--patch', '-p')
        'fetch'    = @('--all', '--prune', '--prune-tags', '--tags', '--force', '--dry-run', '-n', '--quiet', '-q', '--verbose', '-v')
        'log'      = @('--oneline', '--graph', '--decorate', '--stat', '--patch', '-p', '--name-only', '--name-status', '--follow', '--since', '--until')
        'merge'    = @('--no-ff', '--ff-only', '--squash', '--no-commit', '--abort', '--continue', '--strategy', '-s')
        'pull'     = @('--rebase', '--no-rebase', '--ff-only', '--all', '--prune', '--tags', '--quiet', '-q', '--verbose', '-v')
        'push'     = @('--all', '--tags', '--force', '-f', '--force-with-lease', '--set-upstream', '-u', '--delete', '--dry-run', '-n', '--follow-tags', '--atomic')
        'rebase'   = @('--continue', '--abort', '--skip', '--interactive', '-i', '--onto', '--rebase-merges', '--autosquash', '--autostash')
        'reset'    = @('--soft', '--mixed', '--hard', '--merge', '--keep', '--patch', '-p')
        'restore'  = @('--staged', '--worktree', '--source', '--patch', '-p')
        'rm'       = @('--cached', '--force', '-f', '--recursive', '-r', '--dry-run', '-n')
        'show'     = @('--stat', '--name-only', '--name-status', '--patch', '-p', '--oneline')
        'stash'    = @('--all', '-a', '--include-untracked', '-u', '--patch', '-p', '--keep-index', '--message', '-m')
        'status'   = @('--short', '-s', '--branch', '-b', '--porcelain', '--show-stash', '--untracked-files')
        'tag'      = @('--list', '-l', '--annotate', '-a', '--delete', '-d', '--force', '-f', '--sort', '--contains')
        'worktree' = @('--porcelain', '--verbose', '-v', '--expire', '--reason', '--detach', '-d', '--checkout', '--force', '-f', '--lock', '--orphan', '--track', '--guess-remote', '--quiet', '-q')
    }

    $completeFlags = {
        param([string]$command)
        $flags = @($globalGitFlags)
        if ($subcommandFlags.ContainsKey($command)) {
            $flags += $subcommandFlags[$command]
        }
        & $completeList $flags
    }

    $getConfigKeys = {
        @(
            'user.name',
            'user.email',
            'core.editor',
            'core.autocrlf',
            'core.safecrlf',
            'core.filemode',
            'core.ignorecase',
            'init.defaultBranch',
            'pull.rebase',
            'pull.ff',
            'push.default',
            'push.autoSetupRemote',
            'fetch.prune',
            'merge.ff',
            'merge.conflictStyle',
            'rebase.autoStash',
            'rebase.autoSquash',
            'rerere.enabled',
            'credential.helper',
            'credential.useHttpPath',
            'alias.co',
            'alias.br',
            'alias.ci',
            'alias.st'
        )
    }

    $getCurrentBranch = {
        git symbolic-ref --short HEAD 2>$null
    }

    $getNewBranchSuggestions = {
        $currentBranch = & $getCurrentBranch
        $names = @(
            'feature/',
            'bugfix/',
            'hotfix/',
            'chore/',
            'docs/',
            'refactor/',
            'test/'
        )

        if (-not [string]::IsNullOrWhiteSpace($currentBranch)) {
            $names += @(
                "$currentBranch-fix",
                "$currentBranch-update"
            )
        }

        $names
    }

    $preferredSubcommands = @(
        'status',
        'add',
        'commit',
        'push',
        'pull',
        'fetch',
        'switch',
        'checkout',
        'branch',
        'merge',
        'rebase',
        'log',
        'diff',
        'stash',
        'tag',
        'restore',
        'reset',
        'rm'
    )

    if ($argIndex -le 0) {
        if ($wordToComplete -like '-*') {
            & $completeList $globalGitFlags
            return
        }

        $subcommands = @(
            git --list-cmds=main, others, alias, nohelpers 2>$null
        )

        if (-not $subcommands -or $subcommands.Count -eq 0) {
            $subcommands = @(
                'add', 'bisect', 'branch', 'checkout', 'cherry-pick', 'clean', 'clone', 'commit', 'diff',
                'fetch', 'grep', 'init', 'log', 'merge', 'mv', 'pull', 'push', 'rebase', 'reset', 'restore',
                'revert', 'rm', 'show', 'stash', 'status', 'switch', 'tag', 'worktree'
            )
        }

        $allSubcommands = @(
            $subcommands |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )

        $orderedSubcommands = @()
        foreach ($name in $preferredSubcommands) {
            if ($allSubcommands -contains $name) {
                $orderedSubcommands += $name
            }
        }

        $orderedSubcommands += @(
            $allSubcommands |
                Where-Object { $preferredSubcommands -notcontains $_ } |
                Sort-Object
        )

        $orderedSubcommands |
            Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { & $newResult $_ }
        return
    }

    $subcommand = $tokens[1]

    if ($wordToComplete -like '-*') {
        if ($subcommand -ne 'worktree' -or $argIndex -le 1) {
            & $completeFlags $subcommand
            return
        }
    }

    if ($subcommand -eq 'worktree') {
        $worktreeSubcommands = @('add', 'list', 'lock', 'move', 'prune', 'remove', 'repair', 'unlock')

        if ($argIndex -le 1) {
            & $completeList $worktreeSubcommands
            return
        }

        $worktreeAction = $tokens[2]

        if ($wordToComplete -like '-*') {
            $worktreeActionFlags = @{
                'add'    = @('--detach', '-d', '--checkout', '--force', '-f', '--lock', '--orphan', '--track', '--guess-remote', '--quiet', '-q')
                'list'   = @('--porcelain', '--verbose', '-v')
                'lock'   = @('--reason')
                'move'   = @('--force', '-f')
                'prune'  = @('--expire', '--verbose', '-v')
                'remove' = @('--force', '-f')
                'repair' = @()
                'unlock' = @()
            }

            if ($worktreeActionFlags.ContainsKey($worktreeAction)) {
                & $completeList $worktreeActionFlags[$worktreeAction]
            }
            else {
                & $completeList $worktreeSubcommands
            }
            return
        }

        switch ($worktreeAction) {
            'add' {
                if ($argIndex -ge 3) {
                    & $completeList (& $getRefs)
                }
                return
            }
            { $_ -in @('lock', 'move', 'remove', 'repair', 'unlock') } {
                & $completeList (& $getWorktreePaths)
                return
            }
            'list' {
                return
            }
            'prune' {
                return
            }
            default {
                & $completeList $worktreeSubcommands
                return
            }
        }
    }

    if ($subcommand -eq 'config') {
        & $completeList (& $getConfigKeys)
        return
    }

    switch ($subcommand) {
        { $_ -in @('checkout', 'switch') } {
            if (($subcommand -eq 'checkout' -and ($tokens -contains '-b' -or $tokens -contains '-B')) -or
                ($subcommand -eq 'switch' -and ($tokens -contains '-c' -or $tokens -contains '-C'))) {
                & $completeList (& $getNewBranchSuggestions)
                return
            }

            & $completeList (& $getRefs)
            return
        }
        { $_ -in @('merge', 'rebase', 'reset', 'show', 'log', 'diff', 'cherry-pick', 'revert') } {
            & $completeList (& $getRefs)
            return
        }
        { $_ -in @('push', 'pull', 'fetch', 'remote') } {
            & $completeList (& $getRemotes)
            return
        }
        { $_ -in @('add', 'restore', 'rm', 'mv') } {
            & $completeList (& $getFiles)
            return
        }
        'branch' {
            if ($tokens -contains '-d' -or $tokens -contains '-D' -or $tokens -contains '--delete' -or
                $tokens -contains '-m' -or $tokens -contains '-M' -or $tokens -contains '--move') {
                & $completeList (& $getRefs)
            }
            else {
                & $completeList (& $getRefs)
            }
            return
        }
        default {
            & $completeList (& $getRefs)
            return
        }
    }
}

Register-ArgumentCompleter -Native -CommandName git -ScriptBlock $GitNativeCompleter
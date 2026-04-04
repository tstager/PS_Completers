# Git Native Argument Completer for PowerShell
# Provides intelligent tab completion for git commands, subcommands, and flags.
# This implementation uses git's own capabilities to fetch relevant completions,
# ensuring that it stays up-to-date with the installed version of git.
   
function Complete-GitNative {
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

    $completeOrderedList = {
        param([string]$prefix, [string[]]$values)

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($value in $values) {
            if ([string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            if (-not $seen.Add($value)) {
                continue
            }

            if ($value -like "$prefix*") {
                & $newResult $value
            }
        }
    }

    $completeFileSystemPaths = {
        param(
            [string]$pathPrefix,
            [string]$completionPrefix = '',
            [switch]$DirectoriesOnly
        )

        [System.Management.Automation.CompletionCompleters]::CompleteFilename($pathPrefix) |
            Where-Object {
                -not $DirectoriesOnly -or (Test-Path -LiteralPath $_.CompletionText -PathType Container)
            } |
            ForEach-Object {
                if ([string]::IsNullOrEmpty($completionPrefix)) {
                    $_
                }
                else {
                    $completionText = "$completionPrefix$($_.CompletionText)"
                    [System.Management.Automation.CompletionResult]::new(
                        $completionText,
                        $completionText,
                        'ParameterValue',
                        $completionText
                    )
                }
            }
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

    $getWorktreePaths = {
        @(
            git worktree list --porcelain 2>$null |
                Where-Object { $_ -like 'worktree *' } |
                ForEach-Object { $_.Substring(9) }
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

    if (-not (Get-Variable -Name GitHelpMetadataCache -Scope Global -ErrorAction SilentlyContinue)) {
        $global:GitHelpMetadataCache = @{}
    }

    $documentedNestedSubcommands = @{
        'hook'            = @('run')
        'maintenance'     = @('is-needed', 'register', 'run', 'start', 'stop', 'unregister')
        'notes'           = @('add', 'append', 'copy', 'edit', 'get-ref', 'list', 'merge', 'prune', 'remove', 'show')
        'reflog'          = @('delete', 'drop', 'exists', 'expire', 'list', 'show', 'write')
        'remote'          = @('add', 'get-url', 'prune', 'remove', 'rename', 'rm', 'set-branches', 'set-head', 'set-url', 'show', 'update')
        'sparse-checkout' = @('add', 'check-rules', 'clean', 'disable', 'init', 'list', 'reapply', 'set')
        'stash'           = @('apply', 'branch', 'clear', 'create', 'drop', 'export', 'import', 'list', 'pop', 'push', 'save', 'show', 'store')
        'submodule'       = @('absorbgitdirs', 'add', 'deinit', 'foreach', 'init', 'set-branch', 'set-url', 'status', 'summary', 'sync', 'update')
        'worktree'        = @('add', 'list', 'lock', 'move', 'prune', 'remove', 'repair', 'unlock')
    }

    $getTopLevelSubcommands = {
        if ($global:GitHelpMetadataCache.ContainsKey('<root>')) {
            return $global:GitHelpMetadataCache['<root>'].Subcommands
        }

        $subcommands = @(
            git --list-cmds=main,others,alias,nohelpers 2>$null
        )

        if (-not $subcommands -or $subcommands.Count -eq 0) {
            $subcommands = @(
                'add', 'bisect', 'branch', 'checkout', 'cherry-pick', 'clean', 'clone', 'commit', 'diff',
                'fetch', 'grep', 'hook', 'init', 'log', 'merge', 'mv', 'pull', 'push', 'rebase', 'reset', 'restore',
                'revert', 'rm', 'show', 'stash', 'status', 'switch', 'tag', 'worktree'
            )
        }

        $metadata = [pscustomobject]@{
            Flags       = @($globalGitFlags)
            Subcommands = @(
                $subcommands |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
        }

        $global:GitHelpMetadataCache['<root>'] = $metadata
        $metadata.Subcommands
    }

    $getCommandMetadata = {
        param([string[]]$commandPath)

        $cacheKey = if ($commandPath.Count -gt 0) {
            $commandPath -join ' '
        }
        else {
            '<root>'
        }

        if ($cacheKey -eq '<root>' -and -not $global:GitHelpMetadataCache.ContainsKey($cacheKey)) {
            $null = & $getTopLevelSubcommands
        }

        if ($global:GitHelpMetadataCache.ContainsKey($cacheKey)) {
            return $global:GitHelpMetadataCache[$cacheKey]
        }

        $helpLines = @(
            & git @commandPath -h 2>&1 |
                ForEach-Object { $_.ToString() }
        )

        $flags = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $helpLines) {
            foreach ($match in [regex]::Matches($line, '(?<!\w)(--\[(?:no-)\][A-Za-z0-9][A-Za-z0-9-]*|--[A-Za-z0-9][A-Za-z0-9-]*|-[A-Za-z])')) {
                $option = $match.Value
                if ($option -match '^--\[no-\](.+)$') {
                    $flags.Add("--$($Matches[1])")
                    $flags.Add("--no-$($Matches[1])")
                }
                else {
                    $flags.Add($option)
                }
            }
        }

        $subcommands = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $helpLines) {
            if ($line -notmatch '^\s*(?:usage:|or:)\s+git\s+') {
                continue
            }

            $usage = $line -replace '^\s*(?:usage:|or:)\s+git\s+', ''
            $usageTokens = @(
                [regex]::Matches($usage, '\S+') |
                    ForEach-Object { $_.Value }
            )

            if ($usageTokens.Count -le $commandPath.Count) {
                continue
            }

            $matchesPath = $true
            for ($i = 0; $i -lt $commandPath.Count; $i++) {
                if ($usageTokens[$i] -ne $commandPath[$i]) {
                    $matchesPath = $false
                    break
                }
            }

            if (-not $matchesPath) {
                continue
            }

            $usageRemainder = ($usageTokens[$commandPath.Count..($usageTokens.Count - 1)] -join ' ')

            $alternativesMatch = [regex]::Match(
                $usageRemainder,
                '^\s*[\[(]*(?<commands>[A-Za-z0-9][A-Za-z0-9-]*(?:\s*\|\s*[A-Za-z0-9][A-Za-z0-9-]*)+)'
            )
            if ($alternativesMatch.Success) {
                foreach ($candidate in ($alternativesMatch.Groups['commands'].Value -split '\|')) {
                    $cleanCandidate = $candidate.Trim()
                    if ($cleanCandidate -match '^[A-Za-z0-9][A-Za-z0-9-]*$') {
                        $subcommands.Add($cleanCandidate)
                    }
                }
                continue
            }

            $singleCommandMatch = [regex]::Match(
                $usageRemainder,
                '^\s*[\[(]*(?<command>[A-Za-z0-9][A-Za-z0-9-]*)'
            )
            if ($singleCommandMatch.Success) {
                $subcommands.Add($singleCommandMatch.Groups['command'].Value)
            }
        }

        if ($documentedNestedSubcommands.ContainsKey($cacheKey)) {
            foreach ($documentedSubcommand in $documentedNestedSubcommands[$cacheKey]) {
                $subcommands.Add($documentedSubcommand)
            }
        }

        $metadata = [pscustomobject]@{
            Flags       = @($flags | Sort-Object -Unique)
            Subcommands = @($subcommands | Sort-Object -Unique)
        }

        $global:GitHelpMetadataCache[$cacheKey] = $metadata
        $metadata
    }

    $getCommandContext = {
        param([string[]]$argsBeforeCursor)

        $commandPath = @()
        $metadata = & $getCommandMetadata $commandPath
        $lastNonFlagArgument = $null

        foreach ($argument in $argsBeforeCursor) {
            if ($argument -eq '--') {
                break
            }

            if ($argument.StartsWith('-')) {
                continue
            }

            $lastNonFlagArgument = $argument
            if ($metadata.Subcommands -contains $argument) {
                $commandPath += $argument
                $metadata = & $getCommandMetadata $commandPath
            }
        }

        [pscustomobject]@{
            CommandPath         = @($commandPath)
            Metadata            = $metadata
            LastNonFlagArgument = $lastNonFlagArgument
        }
    }

    $getArgumentsAfterPath = {
        param([string[]]$argsBeforeCursor, [string[]]$commandPath)

        $remainingPath = [System.Collections.Generic.Queue[string]]::new()
        foreach ($segment in $commandPath) {
            $remainingPath.Enqueue($segment)
        }

        $arguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in $argsBeforeCursor) {
            if ($remainingPath.Count -gt 0 -and $argument -eq $remainingPath.Peek()) {
                $null = $remainingPath.Dequeue()
                continue
            }

            if ($remainingPath.Count -gt 0) {
                continue
            }

            $arguments.Add($argument)
        }

        @($arguments)
    }

    $getPositionalArgumentsAfterPath = {
        param([string[]]$argsBeforeCursor, [string[]]$commandPath)

        @(
            & $getArgumentsAfterPath $argsBeforeCursor $commandPath |
                Where-Object { -not $_.StartsWith('-') }
        )
    }

    $analyzeArguments = {
        param(
            [string[]]$arguments,
            [string[]]$optionsWithValues = @()
        )

        $valueOptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($optionName in $optionsWithValues) {
            if (-not [string]::IsNullOrWhiteSpace($optionName)) {
                $null = $valueOptions.Add($optionName)
            }
        }

        $positionals = [System.Collections.Generic.List[string]]::new()
        $pendingValueOption = $null
        $afterDoubleDash = $false

        foreach ($argument in $arguments) {
            if ($afterDoubleDash) {
                $positionals.Add($argument)
                continue
            }

            if ($argument -eq '--') {
                $afterDoubleDash = $true
                continue
            }

            if ($pendingValueOption) {
                $pendingValueOption = $null
                continue
            }

            if ($argument.StartsWith('-')) {
                $optionName = $argument
                $hasAttachedValue = $false

                $attachedLongOptionMatch = [regex]::Match(
                    $argument,
                    '^(?<option>--[A-Za-z0-9][A-Za-z0-9-]*)='
                )
                if ($attachedLongOptionMatch.Success) {
                    $optionName = $attachedLongOptionMatch.Groups['option'].Value
                    $hasAttachedValue = $true
                }

                if ($valueOptions.Contains($optionName) -and -not $hasAttachedValue) {
                    $pendingValueOption = $optionName
                }

                continue
            }

            $positionals.Add($argument)
        }

        [pscustomobject]@{
            Positionals        = @($positionals)
            PendingValueOption = $pendingValueOption
            AfterDoubleDash    = $afterDoubleDash
        }
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

    $getHookNames = {
        $defaultHookNames = @(
            'applypatch-msg',
            'pre-applypatch',
            'post-applypatch',
            'pre-commit',
            'pre-merge-commit',
            'prepare-commit-msg',
            'commit-msg',
            'post-commit',
            'pre-rebase',
            'post-checkout',
            'post-merge',
            'pre-push',
            'pre-receive',
            'update',
            'proc-receive',
            'post-receive',
            'post-update',
            'reference-transaction',
            'push-to-checkout',
            'pre-auto-gc',
            'post-rewrite',
            'sendemail-validate',
            'fsmonitor-watchman'
        )

        $repoHookNames = @()
        $hooksPath = git rev-parse --git-path hooks 2>$null
        if (-not [string]::IsNullOrWhiteSpace($hooksPath)) {
            $repoHookNames = @(
                Get-ChildItem -Path $hooksPath -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notlike '*.sample' } |
                    ForEach-Object { $_.BaseName }
            )
        }

        @($defaultHookNames + $repoHookNames) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
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

    $getInitBranchSuggestions = {
        $configuredBranch = git config --get init.defaultBranch 2>$null
        @(
            $configuredBranch
            'main'
            'master'
            'develop'
            'trunk'
        ) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    }

    $getInitFlagCompletions = {
        param([string[]]$metadataFlags)

        $preferredFlags = @(
            '--quiet',
            '-q',
            '--bare',
            '--template=',
            '--separate-git-dir',
            '--object-format=',
            '--ref-format=',
            '-b',
            '--initial-branch=',
            '--shared',
            '--shared='
        )

        $remainingFlags = @(
            $metadataFlags |
                Where-Object { $_ -notin @('--template', '--object-format', '--ref-format', '--initial-branch') }
        )

        @($preferredFlags + $remainingFlags)
    }

    $completeInitOptionValues = {
        param(
            [string]$optionName,
            [string]$valuePrefix,
            [switch]$Attached
        )

        switch ($optionName) {
            '--template' {
                $completionPrefix = if ($Attached) { '--template=' } else { '' }
                & $completeFileSystemPaths $valuePrefix $completionPrefix -DirectoriesOnly
                return
            }
            '--separate-git-dir' {
                $completionPrefix = if ($Attached) { '--separate-git-dir=' } else { '' }
                & $completeFileSystemPaths $valuePrefix $completionPrefix -DirectoriesOnly
                return
            }
            '--object-format' {
                $values = @('sha1', 'sha256')
                if ($Attached) {
                    & $completeOrderedList $wordToComplete ($values | ForEach-Object { "--object-format=$_" })
                }
                else {
                    & $completeOrderedList $valuePrefix $values
                }
                return
            }
            '--ref-format' {
                $values = @('files', 'reftable')
                if ($Attached) {
                    & $completeOrderedList $wordToComplete ($values | ForEach-Object { "--ref-format=$_" })
                }
                else {
                    & $completeOrderedList $valuePrefix $values
                }
                return
            }
            { $_ -in @('-b', '--initial-branch') } {
                $values = @(& $getInitBranchSuggestions)
                if ($Attached) {
                    & $completeOrderedList $wordToComplete ($values | ForEach-Object { "--initial-branch=$_" })
                }
                else {
                    & $completeOrderedList $valuePrefix $values
                }
                return
            }
            '--shared' {
                $values = @('false', 'true', 'umask', 'group', 'all', 'world', 'everybody', '0640', '0660', '0770')
                if ($Attached) {
                    & $completeOrderedList $wordToComplete ($values | ForEach-Object { "--shared=$_" })
                }
                else {
                    & $completeOrderedList $valuePrefix $values
                }
                return
            }
        }
    }

    $preferredSubcommands = @(
        'status',
        'add',
        'commit',
        'push',
        'pull',
        'fetch',
        'hook',
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

        $allSubcommands = @(& $getTopLevelSubcommands)

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

    $argsBeforeCursor = @()
    if ($argIndex -ge 1) {
        $argsBeforeCursor = @($tokens[1..$argIndex])
    }

    $commandContext = & $getCommandContext $argsBeforeCursor
    $commandPath = @($commandContext.CommandPath)
    $commandText = $commandPath -join ' '
    $subcommand = if ($commandPath.Count -gt 0) { $commandPath[0] } else { $null }
    $argsAfterPath = @(& $getArgumentsAfterPath $argsBeforeCursor $commandPath)
    $positionalsAfterPath = @(& $getPositionalArgumentsAfterPath $argsBeforeCursor $commandPath)

    if ($commandText -eq 'init') {
        $attachedInitValueMatch = [regex]::Match(
            $wordToComplete,
            '^(?<option>--template|--separate-git-dir|--object-format|--ref-format|--initial-branch|--shared)=(?<value>.*)$'
        )
        if ($attachedInitValueMatch.Success) {
            & $completeInitOptionValues $attachedInitValueMatch.Groups['option'].Value $attachedInitValueMatch.Groups['value'].Value -Attached
            return
        }

        if ($argsAfterPath.Count -gt 0) {
            $previousInitArgument = $argsAfterPath[-1]
            if ($previousInitArgument -in @('--template', '--separate-git-dir', '--object-format', '--ref-format', '-b', '--initial-branch', '--shared')) {
                & $completeInitOptionValues $previousInitArgument $wordToComplete
                return
            }
        }
    }

    if ($subcommand -eq 'config') {
        $attachedConfigFileMatch = [regex]::Match(
            $wordToComplete,
            '^(?<option>--file)=(?<value>.*)$'
        )
        if ($attachedConfigFileMatch.Success) {
            & $completeFileSystemPaths $attachedConfigFileMatch.Groups['value'].Value '--file='
            return
        }
    }

    if ($wordToComplete -like '-*') {
        if ($commandText -eq 'init') {
            & $completeOrderedList $wordToComplete (& $getInitFlagCompletions $commandContext.Metadata.Flags)
        }
        else {
            & $completeList $commandContext.Metadata.Flags
        }
        return
    }

    if ($subcommand -eq 'config') {
        $configAnalysis = & $analyzeArguments $argsAfterPath @('-f', '--file', '--blob', '--type', '--default', '--comment')

        if ($configAnalysis.PendingValueOption -in @('-f', '--file')) {
            & $completeFileSystemPaths $wordToComplete
            return
        }

        switch ($commandText) {
            'config' {
                if ($configAnalysis.Positionals.Count -eq 0) {
                    & $completeOrderedList $wordToComplete @($commandContext.Metadata.Subcommands + (& $getConfigKeys))
                    return
                }
            }
            { $_ -in @('config get', 'config set', 'config unset') } {
                if ($configAnalysis.Positionals.Count -eq 0) {
                    & $completeList (& $getConfigKeys)
                    return
                }
            }
        }
    }

    if ($commandContext.Metadata.Subcommands.Count -gt 0) {
        $isAtSubcommandBoundary = [string]::IsNullOrWhiteSpace($commandContext.LastNonFlagArgument)
        if (-not $isAtSubcommandBoundary -and $commandPath.Count -gt 0) {
            $isAtSubcommandBoundary = $commandContext.LastNonFlagArgument -eq $commandPath[-1]
        }

        if ($commandPath.Count -eq 0) {
            $isAtSubcommandBoundary = $true
        }

        if ($isAtSubcommandBoundary) {
            & $completeList $commandContext.Metadata.Subcommands
            return
        }
    }

    $shouldCompleteLeafFlags = (
        $hasTrailingSpace -and
        [string]::IsNullOrEmpty($wordToComplete) -and
        $commandPath.Count -gt 0 -and
        $positionalsAfterPath.Count -eq 0 -and
        $commandContext.Metadata.Subcommands.Count -eq 0
    )

    if ($commandText -eq 'hook run') {
        if ($argsAfterPath.Count -gt 0 -and $argsAfterPath[-1] -eq '--to-stdin') {
            return
        }

        $hookName = $null
        for ($i = 0; $i -lt $argsAfterPath.Count; $i++) {
            $token = $argsAfterPath[$i]

            if ($token -eq '--') {
                break
            }

            if ($token -eq '--to-stdin') {
                $i++
                continue
            }

            if ($token -like '--to-stdin=*' -or $token.StartsWith('-')) {
                continue
            }

            $hookName = $token
            break
        }

        if (-not $hookName) {
            & $completeList (& $getHookNames)
        }

        return
    }

    switch ($commandText) {
        'worktree add' {
            if ($positionalsAfterPath.Count -ge 1) {
                & $completeList (& $getRefs)
            }
            return
        }
        { $_ -in @('worktree lock', 'worktree move', 'worktree remove', 'worktree repair', 'worktree unlock') } {
            & $completeList (& $getWorktreePaths)
            return
        }
        'worktree list' {
            return
        }
        'worktree prune' {
            return
        }
        { $_ -in @('remote remove', 'remote rm') } {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
            }
            return
        }
        'remote rename' {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
            }
            return
        }
        'remote set-head' {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
            }
            elseif ($positionalsAfterPath.Count -lt 2) {
                & $completeList (& $getRefs)
            }
            return
        }
        { $_ -in @('remote show', 'remote prune', 'remote update', 'remote get-url') } {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
            }
            return
        }
        'remote set-branches' {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
            }
            else {
                & $completeList (& $getRefs)
            }
            return
        }
        'remote set-url' {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
            }
            return
        }
    }

    switch ($subcommand) {
        { $_ -in @('checkout', 'switch') } {
            $branchCreationOptions = if ($subcommand -eq 'checkout') { @('-b', '-B') } else { @('-c', '-C') }
            $branchCreationAnalysis = & $analyzeArguments $argsAfterPath $branchCreationOptions
            if ($branchCreationAnalysis.PendingValueOption -in $branchCreationOptions) {
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
        { $_ -in @('push', 'pull', 'fetch') } {
            & $completeList (& $getRemotes)
            return
        }
        { $_ -in @('add', 'restore', 'rm', 'mv') } {
            & $completeList (& $getFiles)
            return
        }
        'branch' {
            & $completeList (& $getRefs)
            return
        }
        default {
            if ($commandText -eq 'init' -and $shouldCompleteLeafFlags) {
                & $completeOrderedList '' (& $getInitFlagCompletions $commandContext.Metadata.Flags)
                & $completeFileSystemPaths '' -DirectoriesOnly
                return
            }

            if ($shouldCompleteLeafFlags) {
                & $completeList $commandContext.Metadata.Flags
                return
            }

            return
        }
    }
}

Register-ArgumentCompleter -Native -CommandName @('git', 'git.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-GitNative -wordToComplete $wordToComplete -commandAst $commandAst -cursorPosition $cursorPosition
}

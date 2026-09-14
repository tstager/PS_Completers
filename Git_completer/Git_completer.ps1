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

    # $cursorPosition indexes the whole input line while $line is command-relative, and only the
    # tokens that start before the cursor may be considered: otherwise mid-line completion treats
    # the word under the cursor as an already-chosen subcommand.
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $isPastCommandEnd = $relativeCursor -gt $line.Length
    $boundedCursor = [Math]::Min([Math]::Max($relativeCursor, 0), $line.Length)

    $tokens = @(
        [regex]::Matches($line, '\S+') |
            Where-Object { $_.Index -lt $boundedCursor } |
            ForEach-Object { $_.Value }
    )

    if ($tokens.Count -eq 0) {
        return
    }

    $hasTrailingSpace = $isPastCommandEnd -or ($line.Substring(0, $boundedCursor) -match '\s$')
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
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($wordToComplete) + '*') } |
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

            if ($value -like ([System.Management.Automation.WildcardPattern]::Escape($prefix) + '*')) {
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
            ForEach-Object {
                # CompleteFilename quotes a path that needs it; the quotes have to come off before
                # the option prefix is attached, or they land in the middle of the token and git
                # receives a literal quote inside the path.
                $rawPath = $_.CompletionText.Trim([char[]]@([char]39, [char]34))

                if ($DirectoriesOnly -and -not (Test-Path -LiteralPath $rawPath -PathType Container)) {
                    return
                }

                if ([string]::IsNullOrEmpty($completionPrefix)) {
                    $_
                    return
                }

                $completionText = "$completionPrefix$rawPath"
                if ($completionText -match '\s') {
                    $completionText = "'" + $completionText.Replace("'", "''") + "'"
                }

                [System.Management.Automation.CompletionResult]::new(
                    $completionText,
                    $completionText,
                    'ParameterValue',
                    $completionText
                )
            }
    }

    $getRefs = {
        @(
            git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags 2>$null
            git rev-parse --short HEAD 2>$null
        ) | Where-Object { $_ }
    }

    $getLocalBranches = {
        @(git for-each-ref --format='%(refname:short)' refs/heads 2>$null) | Where-Object { $_ }
    }

    $getTags = {
        @(git for-each-ref --format='%(refname:short)' refs/tags 2>$null) | Where-Object { $_ }
    }

    # Branch names on one remote, without the '<remote>/' prefix, as fetch/pull refspecs name them.
    $getRemoteBranches = {
        param([string]$remoteName)

        $prefix = "$remoteName/"
        @(git for-each-ref --format='%(refname:short)' "refs/remotes/$remoteName" 2>$null) |
            Where-Object { $_ -and $_.StartsWith($prefix) } |
            ForEach-Object { $_.Substring($prefix.Length) } |
            Where-Object { $_ -ne 'HEAD' }
    }

    $getStashEntries = {
        @(git stash list --format='%gd' 2>$null) | Where-Object { $_ }
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

    # Fallback for the root option list; the live list is parsed from the usage block of
    # 'git --help' by $getGlobalFlags below.
    $globalGitFlags = @(
        '-v',
        '--version',
        '-h',
        '--help',
        '-C',
        '-c',
        '--exec-path',
        '--html-path',
        '--man-path',
        '--info-path',
        '-p',
        '--paginate',
        '-P',
        '--no-pager',
        '--no-replace-objects',
        '--no-lazy-fetch',
        '--no-optional-locks',
        '--no-advice',
        '--bare',
        '--git-dir',
        '--work-tree',
        '--namespace',
        '--config-env'
    )

    $globalGitFlagsWithValues = @(
        '-C',
        '-c',
        '--git-dir',
        '--work-tree',
        '--namespace',
        '--exec-path',
        '--config-env'
    )

    $globalGitDirectoryFlags = @('-C', '--git-dir', '--work-tree')

    if (-not (Get-Variable -Name GitHelpMetadataCache -Scope Global -ErrorAction Ignore)) {
        $global:GitHelpMetadataCache = @{}
    }

    # One local handle to the session cache; the hashtable is shared by reference.
    $metadataCache = $global:GitHelpMetadataCache

    $getGitAliases = {
        if ($metadataCache.ContainsKey('<aliases>')) {
            return $metadataCache['<aliases>']
        }

        $aliases = @{}
        foreach ($configLine in @(git config --get-regexp '^alias\.' 2>$null)) {
            if ($configLine -match '^alias\.(?<name>\S+)\s+(?<body>.*)$') {
                $aliases[$matches['name']] = $matches['body']
            }
        }

        $metadataCache['<aliases>'] = $aliases
        $aliases
    }

    # The root usage block of 'git --help' lists every global option in bracket groups
    # ('[-v | --version] [-C <path>] [--no-advice] ...'), so the list follows the installed git.
    $getGlobalFlags = {
        if ($metadataCache.ContainsKey('<global-flags>')) {
            return $metadataCache['<global-flags>']
        }

        $flags = [System.Collections.Generic.List[string]]::new()
        $inUsage = $false
        foreach ($helpLine in @($null | git --help 2>$null)) {
            if ($helpLine -match '^usage:\s+git\b') {
                $inUsage = $true
            }
            elseif ($inUsage -and [string]::IsNullOrWhiteSpace($helpLine)) {
                break
            }

            if (-not $inUsage) {
                continue
            }

            foreach ($match in [regex]::Matches($helpLine, '(?<=[\[\s|])(-[A-Za-z]|--[A-Za-z][A-Za-z0-9-]*)(?=[\s\]|=])')) {
                $flags.Add($match.Value)
            }
        }

        $result = if ($flags.Count -gt 0) { @($flags | Select-Object -Unique) } else { @($globalGitFlags) }
        $metadataCache['<global-flags>'] = $result
        $result
    }

    $getCompletionScriptData = {
        if ($metadataCache.ContainsKey('<completion-script>')) {
            return $metadataCache['<completion-script>']
        }

        $data = [pscustomobject]@{
            Variables = @{}
            Lines     = @()
        }
        $metadataCache['<completion-script>'] = $data

        $gitCommand = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $gitCommand -or [string]::IsNullOrWhiteSpace($gitCommand.Source)) {
            return $data
        }

        # git.exe can resolve from <root>\cmd, <root>\bin or <root>\mingw64\bin, so no fixed number
        # of Split-Path hops finds the install root. Walk upward from the resolved directory and
        # from 'git --exec-path' (<root>\mingw64\libexec\git-core), probing the completion script
        # at each level; the first hit wins.
        $startDirectories = [System.Collections.Generic.List[string]]::new()
        $startDirectories.Add((Split-Path -Path $gitCommand.Source -Parent))
        $execPath = [string](@($null | git --exec-path 2>$null) | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($execPath)) {
            $startDirectories.Add($execPath.Replace('/', '\'))
        }

        $relativeCandidates = @(
            'share\git\completion\git-completion.bash',
            'mingw64\share\git\completion\git-completion.bash',
            'mingw32\share\git\completion\git-completion.bash',
            'usr\share\git\completion\git-completion.bash'
        )

        $scriptPath = $null
        foreach ($startDirectory in $startDirectories) {
            $directory = $startDirectory
            for ($level = 0; $level -lt 5 -and -not $scriptPath -and -not [string]::IsNullOrWhiteSpace($directory); $level++) {
                foreach ($relativePath in $relativeCandidates) {
                    $candidate = Join-Path -Path $directory -ChildPath $relativePath
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $scriptPath = $candidate
                        break
                    }
                }

                $directory = Split-Path -Path $directory -Parent
            }

            if ($scriptPath) {
                break
            }
        }

        if (-not $scriptPath) {
            return $data
        }

        $scriptLines = @(
            try {
                Get-Content -LiteralPath $scriptPath -ErrorAction Stop
            }
            catch {
                @()
            }
        )

        # The bundled bash completion keeps its option lists in '__git_<name>="..."' assignments
        # that may span several lines.
        $variables = @{}
        $pendingName = $null
        $pendingValue = $null
        foreach ($scriptLine in $scriptLines) {
            if ($null -eq $pendingName) {
                if ($scriptLine -match '^__git_([A-Za-z0-9_]+)="(.*)$') {
                    $pendingName = $matches[1]
                    $remainder = $matches[2]
                    if ($remainder -match '^(.*)"\s*$') {
                        $variables[$pendingName] = $matches[1]
                        $pendingName = $null
                    }
                    else {
                        $pendingValue = $remainder
                    }
                }

                continue
            }

            if ($scriptLine -match '^(.*)"\s*$') {
                $variables[$pendingName] = "$pendingValue $($matches[1])"
                $pendingName = $null
                $pendingValue = $null
            }
            else {
                $pendingValue = "$pendingValue $scriptLine"
            }
        }

        $data.Variables = $variables
        $data.Lines = $scriptLines
        $data
    }

    $expandCompletionScriptWord = {
        param([string]$word, [hashtable]$variables, [System.Collections.Generic.HashSet[string]]$visited, [System.Collections.Generic.List[string]]$sink)

        if ($word -match '^\$__git_([A-Za-z0-9_]+)$') {
            $variableName = $matches[1]
            if (-not $visited.Add($variableName) -or -not $variables.ContainsKey($variableName)) {
                return
            }

            foreach ($rawInner in ($variables[$variableName] -split '\s+')) {
                & $expandCompletionScriptWord $rawInner.Trim([char[]]@([char]34, [char]39)) $variables $visited $sink
            }

            return
        }

        if ($word -match '^--[A-Za-z0-9][A-Za-z0-9-]*=?$') {
            [void]$sink.Add(($word -replace '=$', ''))
        }
    }

    $getCompletionScriptOptions = {
        param([string]$functionName)

        $data = & $getCompletionScriptData
        if (@($data.Lines).Count -eq 0) {
            return @()
        }

        $start = -1
        for ($i = 0; $i -lt $data.Lines.Count; $i++) {
            if ($data.Lines[$i] -match ('^' + [regex]::Escape($functionName) + '\s*\(\)\s*$')) {
                $start = $i
                break
            }
        }

        if ($start -lt 0) {
            return @()
        }

        $collected = [System.Collections.Generic.List[string]]::new()
        for ($i = $start + 1; $i -lt $data.Lines.Count; $i++) {
            if ($data.Lines[$i] -match '^\}') {
                break
            }

            foreach ($rawWord in ($data.Lines[$i] -split '\s+')) {
                $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                & $expandCompletionScriptWord $rawWord.Trim([char[]]@([char]34, [char]39)) $data.Variables $visited $collected
            }
        }

        @($collected | Sort-Object -Unique)
    }

    # git deliberately prints an abbreviated '-h' for the revision-walking commands, so their real
    # option surface is read from the bash completion script that ships with git.
    $completionScriptFunctions = @{
        'log'         = '__git_complete_log_opts'
        'whatchanged' = '__git_complete_log_opts'
        'show'        = '_git_show'
        'diff'        = '_git_diff'
    }

    # The same script holds the value lists for the options those commands document only there.
    $completionScriptValueVariables = @{
        '--pretty'             = 'log_pretty_formats'
        '--format'             = 'log_pretty_formats'
        '--date'               = 'log_date_formats'
        '--diff-algorithm'     = 'diff_algorithms'
        '--submodule'          = 'diff_submodule_formats'
        '--ws-error-highlight' = 'ws_error_highlight_opts'
        '--color-moved'        = 'color_moved_opts'
        '--color-moved-ws'     = 'color_moved_ws_opts'
        '--diff-merges'        = 'diff_merges_opts'
    }

    $getCompletionScriptValues = {
        param([string]$variableName)

        $data = & $getCompletionScriptData
        if (-not $data.Variables.ContainsKey($variableName)) {
            return @()
        }

        @($data.Variables[$variableName] -split '\s+' | Where-Object { $_ })
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
        if ($metadataCache.ContainsKey('<root>')) {
            return $metadataCache['<root>'].Subcommands
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
            Flags              = @($globalGitFlags)
            Subcommands        = @(
                $subcommands |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
            OptionSpecs        = @{}
            OptionDescriptions = @{}
        }

        $metadataCache['<root>'] = $metadata
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

        if ($cacheKey -eq '<root>' -and -not $metadataCache.ContainsKey($cacheKey)) {
            $null = & $getTopLevelSubcommands
        }

        if ($metadataCache.ContainsKey($cacheKey)) {
            return $metadataCache[$cacheKey]
        }

        # Never run '-h' against a user alias: git has no help to print for a shell alias
        # ('!cmd ...') and runs the alias body instead, so completion would execute it.
        if ($commandPath.Count -ge 1) {
            $aliasTable = & $getGitAliases
            if ($aliasTable.ContainsKey($commandPath[0])) {
                $aliasBody = [string]$aliasTable[$commandPath[0]]
                $aliasMetadata = $null

                if (-not $aliasBody.StartsWith('!')) {
                    $aliasTarget = @($aliasBody -split '\s+' | Where-Object { $_ }) | Select-Object -First 1
                    if ($aliasTarget -and
                        $aliasTarget -match '^[A-Za-z0-9][A-Za-z0-9-]*$' -and
                        -not $aliasTable.ContainsKey($aliasTarget)) {
                        $aliasMetadata = & $getCommandMetadata (@($aliasTarget) + @($commandPath | Select-Object -Skip 1))
                    }
                }

                if (-not $aliasMetadata) {
                    $aliasMetadata = [pscustomobject]@{
                        Flags              = @()
                        Subcommands        = @()
                        OptionSpecs        = @{}
                        OptionDescriptions = @{}
                    }
                }

                $metadataCache[$cacheKey] = $aliasMetadata
                return $aliasMetadata
            }
        }

        $helpLines = @(
            & git @commandPath -h 2>&1 |
                ForEach-Object { $_.ToString() }
        )

        $optionPattern = '(?<!\w)(--\[(?:no-)\][A-Za-z0-9][A-Za-z0-9-]*|--[A-Za-z0-9][A-Za-z0-9-]*|-[A-Za-z])'
        $flags = [System.Collections.Generic.List[string]]::new()
        $optionSpecs = @{}
        $optionDescriptions = @{}
        $describedOptions = @()
        foreach ($line in $helpLines) {
            foreach ($match in [regex]::Matches($line, $optionPattern)) {
                $option = $match.Value
                if ($option -match '^--\[no-\](.+)$') {
                    $flags.Add("--$($Matches[1])")
                    $flags.Add("--no-$($Matches[1])")
                }
                else {
                    $flags.Add($option)
                }
            }

            # The option column of an option row carries the argument the option takes, for
            # example '-F, --[no-]file <file>' or '--[no-]conflict <style>'. Everything after the
            # last option token in that column is that argument's spec, and the description
            # column (same line, or the indented continuation lines) may spell out the values
            # a bare placeholder stands for ('optional modes: all, normal, no').
            if ($line -notmatch '^\s{4}\S') {
                if ($describedOptions.Count -gt 0 -and $line -match '^\s{6,}\S') {
                    foreach ($describedOption in $describedOptions) {
                        $optionDescriptions[$describedOption] = ($optionDescriptions[$describedOption] + ' ' + $line.Trim()).Trim()
                    }
                }
                else {
                    $describedOptions = @()
                }

                continue
            }

            $columns = @($line.Trim() -split '\s{2,}', 2)
            $optionColumn = $columns[0]
            $description = if ($columns.Count -gt 1) { $columns[1].Trim() } else { '' }
            $columnMatches = @([regex]::Matches($optionColumn, $optionPattern))
            if ($columnMatches.Count -eq 0) {
                $describedOptions = @()
                continue
            }

            $describedOptions = @(
                foreach ($columnMatch in $columnMatches) {
                    $specOption = $columnMatch.Value
                    if ($specOption -match '^--\[no-\](.+)$') {
                        $specOption = "--$($Matches[1])"
                    }

                    $optionDescriptions[$specOption] = $description
                    $specOption
                }
            )

            $lastMatch = $columnMatches[$columnMatches.Count - 1]
            $spec = $optionColumn.Substring($lastMatch.Index + $lastMatch.Length).Trim()
            if ([string]::IsNullOrWhiteSpace($spec)) {
                continue
            }

            # A long option column can run into its description with a single space
            # ('--[no-]cleanup <mode> how to strip spaces ...'); keep only the argument spec.
            $specSplit = [regex]::Match($spec, '^(?<spec>\[?=?(?:<[^>]+>|\([^)]*\))\]?)\s+(?<rest>\S.*)$')
            if ($specSplit.Success) {
                $spec = $specSplit.Groups['spec'].Value
                if ([string]::IsNullOrWhiteSpace($description)) {
                    foreach ($describedOption in $describedOptions) {
                        $optionDescriptions[$describedOption] = $specSplit.Groups['rest'].Value.Trim()
                    }
                }
            }

            foreach ($specOption in $describedOptions) {
                $optionSpecs[$specOption] = $spec
            }
        }

        if ($completionScriptFunctions.ContainsKey($cacheKey)) {
            foreach ($supplementFlag in @(& $getCompletionScriptOptions $completionScriptFunctions[$cacheKey])) {
                $flags.Add($supplementFlag)
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
            Flags              = @($flags | Sort-Object -Unique)
            Subcommands        = @($subcommands | Sort-Object -Unique)
            OptionSpecs        = $optionSpecs
            OptionDescriptions = $optionDescriptions
        }

        $metadataCache[$cacheKey] = $metadata
        $metadata
    }

    # Values git documents only in prose, or not at all, for placeholder specs such as <mode>,
    # <style>, <strategy> and <option>. Keyed by '<command> <option>'.
    $curatedOptionValues = @{
        'commit --cleanup'          = @('strip', 'whitespace', 'verbatim', 'scissors', 'default')
        'commit -u'                 = @('all', 'normal', 'no')
        'commit --untracked-files'  = @('all', 'normal', 'no')
        'status -u'                 = @('all', 'normal', 'no')
        'status --untracked-files'  = @('all', 'normal', 'no')
        'checkout --conflict'       = @('merge', 'diff3', 'zdiff3')
        'switch --conflict'         = @('merge', 'diff3', 'zdiff3')
        'merge -s'                  = @('ort', 'recursive', 'resolve', 'octopus', 'ours', 'subtree')
        'merge --strategy'          = @('ort', 'recursive', 'resolve', 'octopus', 'ours', 'subtree')
        'rebase -s'                 = @('ort', 'recursive', 'resolve', 'octopus', 'ours', 'subtree')
        'rebase --strategy'         = @('ort', 'recursive', 'resolve', 'octopus', 'ours', 'subtree')
        'pull -s'                   = @('ort', 'recursive', 'resolve', 'octopus', 'ours', 'subtree')
        'pull --strategy'           = @('ort', 'recursive', 'resolve', 'octopus', 'ours', 'subtree')
        'merge -X'                  = @('ours', 'theirs', 'patience', 'diff-algorithm=', 'ignore-space-change', 'ignore-all-space', 'ignore-space-at-eol', 'ignore-cr-at-eol', 'renormalize', 'no-renormalize', 'find-renames=', 'subtree=')
        'merge --strategy-option'   = @('ours', 'theirs', 'patience', 'diff-algorithm=', 'ignore-space-change', 'ignore-all-space', 'ignore-space-at-eol', 'ignore-cr-at-eol', 'renormalize', 'no-renormalize', 'find-renames=', 'subtree=')
        'rebase -X'                 = @('ours', 'theirs', 'patience', 'diff-algorithm=', 'ignore-space-change', 'ignore-all-space', 'ignore-space-at-eol', 'ignore-cr-at-eol', 'renormalize', 'no-renormalize', 'find-renames=', 'subtree=')
        'rebase --strategy-option'  = @('ours', 'theirs', 'patience', 'diff-algorithm=', 'ignore-space-change', 'ignore-all-space', 'ignore-space-at-eol', 'ignore-cr-at-eol', 'renormalize', 'no-renormalize', 'find-renames=', 'subtree=')
        'pull -X'                   = @('ours', 'theirs', 'patience', 'diff-algorithm=', 'ignore-space-change', 'ignore-all-space', 'ignore-space-at-eol', 'ignore-cr-at-eol', 'renormalize', 'no-renormalize', 'find-renames=', 'subtree=')
        'pull --strategy-option'    = @('ours', 'theirs', 'patience', 'diff-algorithm=', 'ignore-space-change', 'ignore-all-space', 'ignore-space-at-eol', 'ignore-cr-at-eol', 'renormalize', 'no-renormalize', 'find-renames=', 'subtree=')
    }

    # A value list spelled out in the description column: 'optional modes: all, normal, no.' or
    # 'conflict style (merge, diff3, or zdiff3)'.
    $getDescribedOptionValues = {
        param([string]$description)

        if ([string]::IsNullOrWhiteSpace($description)) {
            return @()
        }

        $listMatch = [regex]::Match(
            $description,
            '(?:modes?|values?|styles?|one of):\s*(?<values>[A-Za-z0-9_-]+(?:,\s*(?:or\s+)?[A-Za-z0-9_-]+)+)'
        )
        if (-not $listMatch.Success) {
            $listMatch = [regex]::Match(
                $description,
                '\((?<values>[A-Za-z0-9_-]+(?:,\s*(?:or\s+)?[A-Za-z0-9_-]+)+)\)'
            )
        }

        if (-not $listMatch.Success) {
            return @()
        }

        @($listMatch.Groups['values'].Value -split ',' | ForEach-Object { ($_ -replace '^\s*or\s+', '').Trim() } | Where-Object { $_ })
    }

    $getCommandContext = {
        param([string[]]$argsBeforeCursor)

        $commandPath = @()
        $metadata = & $getCommandMetadata $commandPath
        $lastNonFlagArgument = $null
        $pendingGlobalValueOption = $null

        foreach ($argument in $argsBeforeCursor) {
            if ($argument -eq '--') {
                break
            }

            # A global option such as '-C <path>' consumes the token after it, which is otherwise
            # mistaken for the subcommand.
            if ($pendingGlobalValueOption) {
                $pendingGlobalValueOption = $null
                continue
            }

            if ($argument.StartsWith('-')) {
                if ($commandPath.Count -eq 0 -and $globalGitFlagsWithValues -contains $argument) {
                    $pendingGlobalValueOption = $argument
                }

                continue
            }

            $lastNonFlagArgument = $argument
            if ($metadata.Subcommands -contains $argument) {
                $commandPath += $argument
                $metadata = & $getCommandMetadata $commandPath
            }
        }

        [pscustomobject]@{
            CommandPath              = @($commandPath)
            Metadata                 = $metadata
            LastNonFlagArgument      = $lastNonFlagArgument
            PendingGlobalValueOption = $pendingGlobalValueOption
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

    $getHelpGuides = {
        @(git --list-cmds=list-guide 2>$null) | Where-Object { $_ }
    }

    $completeOptionSpecValue = {
        param(
            [string]$spec,
            [string]$valuePrefix,
            [string]$completionPrefix = '',
            [string]$optionName = ''
        )

        if ([string]::IsNullOrWhiteSpace($spec)) {
            return
        }

        $normalized = $spec.Trim().Trim([char[]]@('[', ']'))
        if ($normalized.StartsWith('=')) {
            $normalized = $normalized.Substring(1)
        }

        $normalized = $normalized.Trim([char[]]@('[', ']'))

        $emit = {
            param([string[]]$values)

            if ([string]::IsNullOrEmpty($completionPrefix)) {
                & $completeOrderedList $valuePrefix $values
            }
            else {
                & $completeOrderedList $wordToComplete @($values | ForEach-Object { "$completionPrefix$_" })
            }
        }

        $enumMatch = [regex]::Match(
            $normalized,
            '^\(?(?<values>[A-Za-z0-9][A-Za-z0-9._-]*(?:\|[A-Za-z0-9][A-Za-z0-9._-]*)+)\)?$'
        )
        if ($enumMatch.Success) {
            & $emit @($enumMatch.Groups['values'].Value -split '\|')
            return
        }

        # Curated values and the description column outrank the placeholder word, which is
        # what turns '<mode>', '<style>' and '<option>' into real choices.
        if (-not [string]::IsNullOrWhiteSpace($optionName)) {
            $curatedKey = "$commandText $optionName"
            if ($curatedOptionValues.ContainsKey($curatedKey)) {
                & $emit @($curatedOptionValues[$curatedKey])
                return
            }

            if ($optionDescriptions.ContainsKey($optionName)) {
                $describedValues = @(& $getDescribedOptionValues $optionDescriptions[$optionName])
                if ($describedValues.Count -gt 0) {
                    & $emit $describedValues
                    return
                }
            }
        }

        switch -Regex ($normalized.Trim([char[]]@('<', '>')).ToLowerInvariant()) {
            '^(file|path|dir|directory|template-directory|gitdir|pathspec)$' {
                & $completeFileSystemPaths $valuePrefix $completionPrefix
                return
            }
            '^new-branch$' {
                & $emit @(& $getNewBranchSuggestions)
                return
            }
            '^(commit|commit-ish|committish|object|tree-ish|treeish|rev|revision|ref|reference|branch|start-point|upstream)$' {
                & $emit @(& $getRefs)
                return
            }
        }
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
            & $completeList (& $getGlobalFlags)
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
            Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($wordToComplete) + '*') } |
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

    if ($commandContext.PendingGlobalValueOption) {
        if ($globalGitDirectoryFlags -contains $commandContext.PendingGlobalValueOption) {
            & $completeFileSystemPaths $wordToComplete '' -DirectoriesOnly
        }

        return
    }

    $optionSpecs = if ($commandContext.Metadata.OptionSpecs) { $commandContext.Metadata.OptionSpecs } else { @{} }
    $optionDescriptions = if ($commandContext.Metadata.OptionDescriptions) { $commandContext.Metadata.OptionDescriptions } else { @{} }

    # 'checkout -b/-B' and 'switch -c/-C' name a branch to be created; their '<branch>' spec
    # must not resolve to the existing refs the generic spec handler offers.
    $branchCreationOptions = switch ($subcommand) {
        'checkout' { @('-b', '-B', '--orphan') }
        'switch' { @('-c', '-C', '--orphan') }
        default { @() }
    }

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

    $attachedOptionValueMatch = [regex]::Match(
        $wordToComplete,
        '^(?<option>--[A-Za-z0-9][A-Za-z0-9-]*)=(?<value>.*)$'
    )
    if ($attachedOptionValueMatch.Success) {
        $attachedOption = $attachedOptionValueMatch.Groups['option'].Value
        $attachedValue = $attachedOptionValueMatch.Groups['value'].Value

        if ($completionScriptFunctions.ContainsKey($commandText) -and
            $completionScriptValueVariables.ContainsKey($attachedOption)) {
            $scriptValues = @(& $getCompletionScriptValues $completionScriptValueVariables[$attachedOption])
            if ($scriptValues.Count -gt 0) {
                & $completeOrderedList $wordToComplete @($scriptValues | ForEach-Object { "$attachedOption=$_" })
                return
            }
        }

        if ($attachedOption -in $branchCreationOptions) {
            & $completeOrderedList $wordToComplete @(& $getNewBranchSuggestions | ForEach-Object { "$attachedOption=$_" })
            return
        }

        if ($optionSpecs.ContainsKey($attachedOption)) {
            & $completeOptionSpecValue $optionSpecs[$attachedOption] $attachedValue "$attachedOption=" $attachedOption
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

    if ($argsAfterPath.Count -gt 0) {
        $previousOption = $argsAfterPath[-1]

        if ($previousOption.StartsWith('-') -and
            $completionScriptFunctions.ContainsKey($commandText) -and
            $completionScriptValueVariables.ContainsKey($previousOption)) {
            $scriptValues = @(& $getCompletionScriptValues $completionScriptValueVariables[$previousOption])
            if ($scriptValues.Count -gt 0) {
                & $completeOrderedList $wordToComplete $scriptValues
                return
            }
        }

        if ($previousOption -in $branchCreationOptions) {
            & $completeList (& $getNewBranchSuggestions)
            return
        }

        if ($previousOption.StartsWith('-') -and $optionSpecs.ContainsKey($previousOption)) {
            & $completeOptionSpecValue $optionSpecs[$previousOption] $wordToComplete '' $previousOption
            return
        }
    }

    # After '--' every remaining argument is a pathspec, whatever the command: tracked and
    # untracked files for the index-editing commands, the filesystem for everything else.
    if ($argsAfterPath -contains '--') {
        if ($subcommand -in @('add', 'restore', 'rm', 'mv')) {
            & $completeList (& $getFiles)
        }
        else {
            & $completeFileSystemPaths $wordToComplete
        }

        return
    }

    if ($commandText -eq 'help' -and $positionalsAfterPath.Count -eq 0) {
        & $completeOrderedList $wordToComplete @(@(& $getTopLevelSubcommands) + @(& $getHelpGuides))
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
        { $_ -in @('stash apply', 'stash pop', 'stash drop', 'stash show') } {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getStashEntries)
            }
            return
        }
        'stash branch' {
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getNewBranchSuggestions)
            }
            elseif ($positionalsAfterPath.Count -lt 2) {
                & $completeList (& $getStashEntries)
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
            # 'git push [<repository> [<refspec>...]]': the first slot is a remote, later slots
            # are refspecs (local branches and tags to push; the remote's branches to fetch/pull).
            if ($positionalsAfterPath.Count -lt 1) {
                & $completeList (& $getRemotes)
                return
            }

            if ($subcommand -eq 'push') {
                & $completeList (@(& $getLocalBranches) + @(& $getTags))
                return
            }

            $remoteBranches = @(& $getRemoteBranches $positionalsAfterPath[0])
            if ($remoteBranches.Count -eq 0) {
                $remoteBranches = @(& $getLocalBranches)
            }

            & $completeList $remoteBranches
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
        'tag' {
            $tagNames = @(& $getTags)
            if ($tagNames.Count -gt 0) {
                & $completeList $tagNames
            }
            elseif ($shouldCompleteLeafFlags) {
                & $completeList $commandContext.Metadata.Flags
            }
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

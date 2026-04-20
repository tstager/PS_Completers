<#
.SYNOPSIS
Registers native PowerShell completion for apm and apm.exe.

.DESCRIPTION
The completer is static-first and is derived from the official APM CLI
reference plus the upstream microsoft/apm click command definitions for
documented enum values and aliases.
#>

Set-StrictMode -Version Latest

function New-ApmCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ToolTip,
        [System.Management.Automation.CompletionResultType]$ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue
    )

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $CompletionText,
        $ResultType,
        $ToolTip
    )
}

function Test-ApmStartsWith {
    param(
        [string]$Candidate,
        [string]$Prefix
    )

    if ([string]::IsNullOrEmpty($Prefix)) {
        return $true
    }

    $Candidate.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ApmPathLikeToken {
    param([string]$Token)

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $false
    }

    if ($Token -match '^[a-z][a-z0-9+\-.]*://') {
        return $false
    }

    $Token -match '^(?:\.{1,2}[\\/]|~[\\/]|[A-Za-z]:[\\/]|\\\\|[\\/])'
}

function Get-ApmPathCompletions {
    param(
        [string]$PathPrefix,
        [string]$AttachedPrefix = '',
        [string]$Placeholder = '<path>'
    )

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    foreach ($item in [System.Management.Automation.CompletionCompleters]::CompleteFilename($PathPrefix)) {
        $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) {
            $item.CompletionText
        }
        else {
            "$AttachedPrefix$($item.CompletionText)"
        }

        $results.Add(
            [System.Management.Automation.CompletionResult]::new(
                $completionText,
                $completionText,
                $item.ResultType,
                $completionText
            )
        )
    }

    if ($results.Count -eq 0 -and -not [string]::IsNullOrEmpty($Placeholder)) {
        $placeholderText = if ([string]::IsNullOrEmpty($AttachedPrefix)) {
            $Placeholder
        }
        else {
            "$AttachedPrefix$Placeholder"
        }

        $results.Add((New-ApmCompletionResult -CompletionText $placeholderText -ToolTip $placeholderText))
    }

    $results
}

function Get-ApmClosedValueCompletions {
    param(
        [string[]]$Values,
        [string]$WordToComplete,
        [string]$AttachedPrefix = '',
        [string]$ToolTipPrefix = ''
    )

    foreach ($value in $Values) {
        $completionText = if ([string]::IsNullOrEmpty($AttachedPrefix)) { $value } else { "$AttachedPrefix$value" }
        if (-not (Test-ApmStartsWith -Candidate $completionText -Prefix $WordToComplete)) {
            continue
        }

        $toolTip = if ([string]::IsNullOrEmpty($ToolTipPrefix)) { $value } else { "$ToolTipPrefix$value" }
        New-ApmCompletionResult -CompletionText $completionText -ToolTip $toolTip
    }
}

function Get-ApmFreeformValueCompletions {
    param(
        [string[]]$SuggestedValues,
        [string]$WordToComplete,
        [string]$AttachedPrefix = '',
        [string]$ToolTipPrefix = ''
    )

    $matched = @(
        Get-ApmClosedValueCompletions -Values $SuggestedValues -WordToComplete $WordToComplete -AttachedPrefix $AttachedPrefix -ToolTipPrefix $ToolTipPrefix
    )

    if ($matched.Count -gt 0 -or [string]::IsNullOrEmpty($WordToComplete)) {
        return $matched
    }

    $typedValue = if ([string]::IsNullOrEmpty($AttachedPrefix)) {
        $WordToComplete
    }
    else {
        "$AttachedPrefix$WordToComplete"
    }

    New-ApmCompletionResult -CompletionText $typedValue -ToolTip $typedValue
}

function Get-ApmCompletionCatalog {
    $existingCatalog = Get-Variable -Name ApmCompletionCatalog -Scope Script -ErrorAction Ignore
    if ($null -ne $existingCatalog) {
        return $existingCatalog.Value
    }

    $newCommand = {
        param([string]$Name, [string]$Description)
        [pscustomobject]@{
            Name        = $Name
            Description = $Description
        }
    }

    $newOption = {
        param(
            [string[]]$Tokens,
            [string]$Description,
            [string]$ValueKind = 'flag',
            [string[]]$Values = @()
        )

        foreach ($token in $Tokens) {
            [pscustomobject]@{
                Token       = $token
                Description = $Description
                ValueKind   = $ValueKind
                Values      = @($Values)
            }
        }
    }

    $installRuntimeValues = @('copilot', 'codex', 'vscode')
    $targetValues = @('copilot', 'claude', 'cursor', 'opencode', 'codex', 'vscode', 'agents', 'all')
    $auditFormatValues = @('text', 'json', 'sarif', 'markdown')
    $configKeyValues = @('auto-integrate', 'temp-dir')
    $booleanValues = @('true', 'false', 'yes', 'no', '1', '0')
    $runtimeValues = @('copilot', 'codex', 'llm')
    $countValues = @('0', '1', '4', '8', '10', '20', '50')

    $catalog = [ordered]@{}

    $catalog[''] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'init' 'Initialize new APM project'
            & $newCommand 'install' 'Install dependencies and deploy local content'
            & $newCommand 'uninstall' 'Remove APM packages'
            & $newCommand 'prune' 'Remove orphaned packages'
            & $newCommand 'audit' 'Scan for hidden Unicode characters'
            & $newCommand 'pack' 'Create a portable bundle'
            & $newCommand 'unpack' 'Extract a bundle'
            & $newCommand 'update' 'Update APM to the latest version'
            & $newCommand 'view' 'View package metadata or list remote versions'
            & $newCommand 'outdated' 'Check locked dependencies for updates'
            & $newCommand 'deps' 'Manage APM package dependencies'
            & $newCommand 'mcp' 'Browse MCP server registry'
            & $newCommand 'marketplace' 'Plugin marketplace management'
            & $newCommand 'search' 'Search plugins in a marketplace'
            & $newCommand 'run' 'Execute prompts'
            & $newCommand 'preview' 'Preview compiled scripts'
            & $newCommand 'list' 'List available scripts'
            & $newCommand 'compile' 'Compile APM context into distributed AGENTS.md files'
            & $newCommand 'config' 'Configure APM CLI'
            & $newCommand 'runtime' 'Manage AI runtimes'
            & $newCommand 'info' 'Hidden alias for view'
        )
        Options = @(
            & $newOption @('--version') 'Show version and exit'
            & $newOption @('--help') 'Show help message and exit'
        )
    }

    $catalog['init'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '-y') 'Skip interactive prompts and use auto-detected defaults'
            & $newOption @('--plugin') 'Initialize as a plugin authoring project'
        )
    }

    $catalog['install'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--runtime') 'Target specific runtime only' 'enum' $installRuntimeValues
            & $newOption @('--exclude') 'Exclude specific runtime from installation' 'enum' $installRuntimeValues
            & $newOption @('--only') 'Install only specific dependency type' 'enum' @('apm', 'mcp')
            & $newOption @('--target', '-t') 'Force deployment to a specific target' 'enum' $targetValues
            & $newOption @('--update') 'Update dependencies to latest Git references'
            & $newOption @('--force') 'Overwrite locally-authored files on collision'
            & $newOption @('--dry-run') 'Show what would be installed without installing'
            & $newOption @('--parallel-downloads') 'Max concurrent package downloads' 'freeform' $countValues
            & $newOption @('--verbose') 'Show detailed installation information'
            & $newOption @('--trust-transitive-mcp') 'Trust self-defined MCP servers from transitive packages'
            & $newOption @('--dev') 'Install as development dependency'
            & $newOption @('--global', '-g') 'Install to user scope instead of the current project'
        )
    }

    $catalog['uninstall'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--dry-run') 'Show what would be removed without removing'
            & $newOption @('--verbose', '-v') 'Show detailed removal information'
            & $newOption @('--global', '-g') 'Remove from user scope instead of the current project'
        )
    }

    $catalog['prune'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--dry-run') 'Show what would be removed without removing'
        )
    }

    $catalog['audit'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--file') 'Scan an arbitrary file instead of installed packages' 'path'
            & $newOption @('--strip') 'Remove dangerous characters while preserving info-level content'
            & $newOption @('--dry-run') 'Preview what would be removed without modifying files'
            & $newOption @('--verbose', '-v') 'Show info-level findings and file details'
            & $newOption @('--format', '-f') 'Output format' 'enum' $auditFormatValues
            & $newOption @('--output', '-o') 'Write report to file' 'path'
            & $newOption @('--ci') 'Run lockfile consistency checks for CI/CD gates'
            & $newOption @('--policy') 'Policy source for CI checks' 'policy'
            & $newOption @('--no-cache') 'Force fresh policy fetch'
            & $newOption @('--no-fail-fast') 'Run all checks even after a failure'
        )
    }

    $catalog['pack'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--output', '-o') 'Output directory' 'path'
            & $newOption @('--target', '-t') 'Filter files by target' 'enum' $targetValues
            & $newOption @('--archive') 'Produce a .tar.gz archive instead of a directory'
            & $newOption @('--dry-run') 'List files that would be packed without writing anything'
            & $newOption @('--format') 'Bundle format' 'enum' @('apm', 'plugin')
            & $newOption @('--force') 'On collision, last writer wins instead of first'
        )
    }

    $catalog['unpack'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--output', '-o') 'Target project directory' 'path'
            & $newOption @('--skip-verify') 'Skip completeness verification against the bundle lockfile'
            & $newOption @('--force') 'Deploy despite critical hidden-character findings'
            & $newOption @('--dry-run') 'Show what would be extracted without writing anything'
        )
    }

    $catalog['update'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--check') 'Only check for updates without installing'
        )
    }

    $catalog['view'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Inspect package from user scope'
        )
    }

    $catalog['info'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Inspect package from user scope'
        )
    }

    $catalog['outdated'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Check user-scope dependencies'
            & $newOption @('--verbose', '-v') 'Show extra detail for outdated packages'
            & $newOption @('--parallel-checks', '-j') 'Max concurrent remote checks' 'freeform' $countValues
        )
    }

    $catalog['deps'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'list' 'List installed APM dependencies'
            & $newCommand 'tree' 'Show dependency tree structure'
            & $newCommand 'info' 'Alias for apm view'
            & $newCommand 'clean' 'Remove all APM dependencies'
            & $newCommand 'update' 'Update APM dependencies'
        )
        Options = @()
    }

    $catalog['deps list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'List user-scope packages instead of the current project'
            & $newOption @('--all') 'List packages from both project and user scope'
        )
    }

    $catalog['deps tree'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['deps info'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['deps clean'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--dry-run') 'Show what would be removed without removing'
            & $newOption @('--yes', '-y') 'Skip confirmation prompt'
        )
    }

    $catalog['deps update'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed update information'
            & $newOption @('--force') 'Overwrite locally-authored files on collision'
            & $newOption @('--global', '-g') 'Update user-scope dependencies'
            & $newOption @('--target', '-t') 'Force deployment to a specific target' 'enum' $targetValues
            & $newOption @('--parallel-downloads') 'Max concurrent downloads' 'freeform' $countValues
        )
    }

    $catalog['mcp'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'list' 'List MCP servers'
            & $newCommand 'search' 'Search MCP servers'
            & $newCommand 'show' 'Show MCP server details'
        )
        Options = @()
    }

    $catalog['mcp list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--limit') 'Number of results to show' 'freeform' @('20', '50')
        )
    }

    $catalog['mcp search'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--limit') 'Number of results to show' 'freeform' @('5', '10', '20', '50')
        )
    }

    $catalog['mcp show'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['marketplace'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'add' 'Register a marketplace'
            & $newCommand 'list' 'List registered marketplaces'
            & $newCommand 'browse' 'Browse marketplace plugins'
            & $newCommand 'update' 'Refresh marketplace cache'
            & $newCommand 'remove' 'Remove a registered marketplace'
        )
        Options = @()
    }

    $catalog['marketplace add'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--name', '-n') 'Custom display name for the marketplace' 'freeform' @('<marketplace-name>')
            & $newOption @('--branch', '-b') 'Branch to track' 'freeform' @('<branch>')
            & $newOption @('--host') 'Git host FQDN' 'freeform' @('<host>')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace browse'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace update'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace remove'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '-y') 'Skip confirmation prompt'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['search'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--limit') 'Maximum results to return' 'freeform' @('5', '10', '20', '50')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['run'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--param', '-p') 'Parameter in format name=value' 'freeform' @('<name=value>')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['preview'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--param', '-p') 'Parameter in format name=value' 'freeform' @('<name=value>')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['compile'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--output', '-o') 'Output file path' 'path'
            & $newOption @('--target', '-t') 'Target agent format' 'enum' $targetValues
            & $newOption @('--chatmode') 'Chatmode to prepend to the AGENTS.md file' 'freeform' @('<chatmode>')
            & $newOption @('--dry-run') 'Preview compilation without writing files'
            & $newOption @('--no-links') 'Skip markdown link resolution'
            & $newOption @('--with-constitution') 'Include Spec Kit constitution content'
            & $newOption @('--no-constitution') 'Do not regenerate the constitution block'
            & $newOption @('--watch') 'Auto-regenerate on changes'
            & $newOption @('--validate') 'Validate primitives without compiling'
            & $newOption @('--single-agents') 'Force single-file compilation'
            & $newOption @('--verbose', '-v') 'Show detailed source attribution and optimizer analysis'
            & $newOption @('--local-only') 'Ignore dependencies and compile only local primitives'
            & $newOption @('--clean') 'Remove orphaned generated files'
        )
    }

    $catalog['config'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'get' 'Get a configuration value'
            & $newCommand 'set' 'Set a configuration value'
        )
        Options = @()
    }

    $catalog['config get'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['config set'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['runtime'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'setup' 'Install AI runtime'
            & $newCommand 'list' 'Show installed runtimes'
            & $newCommand 'remove' 'Uninstall runtime'
            & $newCommand 'status' 'Show active runtime and preference order'
        )
        Options = @()
    }

    $catalog['runtime setup'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--version') 'Specific version to install' 'freeform' @('<version>')
            & $newOption @('--vanilla') 'Install runtime without APM configuration'
        )
    }

    $catalog['runtime list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['runtime remove'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes') 'Confirm the action without prompting'
        )
    }

    $catalog['runtime status'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $script:ApmCompletionCatalog = $catalog
    $script:ApmConfigKeyValues = $configKeyValues
    $script:ApmBooleanValues = $booleanValues
    $script:ApmRuntimeValues = $runtimeValues
    $script:ApmInstallRuntimeValues = $installRuntimeValues
    $script:ApmTargetValues = $targetValues

    $script:ApmCompletionCatalog
}

function Get-ApmOptionLookup {
    param($Entry)

    $lookup = @{}
    foreach ($option in $Entry.Options) {
        $lookup[$option.Token] = $option
    }

    $lookup
}

function Get-ApmArgsBeforeCursor {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [string]$WordToComplete,
        [int]$CursorPosition
    )

    $elements = @($CommandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    if ($elements.Count -le 1) {
        return @()
    }

    $arguments = @($elements[1..($elements.Count - 1)])
    $line = $CommandAst.ToString()
    $hasTrailingSpace = ($line -match '\s$') -or ($CursorPosition -gt $line.Length)
    if ($hasTrailingSpace) {
        return $arguments
    }

    if ($arguments.Count -gt 0 -and $arguments[-1] -eq $WordToComplete) {
        if ($arguments.Count -eq 1) {
            return @()
        }

        return @($arguments[0..($arguments.Count - 2)])
    }

    $arguments
}

function Get-ApmCommandContext {
    param([string[]]$ArgsBeforeCursor)

    $catalog = Get-ApmCompletionCatalog
    $currentKey = ''
    $currentEntry = $catalog['']
    $commandPath = [System.Collections.Generic.List[string]]::new()
    $lastPathIndex = -1

    for ($i = 0; $i -lt $ArgsBeforeCursor.Count; $i++) {
        $arg = $ArgsBeforeCursor[$i]
        if ($arg -eq '--') {
            break
        }

        if ($arg.StartsWith('-')) {
            continue
        }

        $match = $currentEntry.Subcommands | Where-Object { $_.Name -eq $arg } | Select-Object -First 1
        if ($null -eq $match) {
            continue
        }

        $commandPath.Add($match.Name)
        $currentKey = if ([string]::IsNullOrEmpty($currentKey)) {
            $match.Name
        }
        else {
            "$currentKey $($match.Name)"
        }

        $currentEntry = $catalog[$currentKey]
        $lastPathIndex = $i
    }

    [pscustomobject]@{
        Key           = $currentKey
        Entry         = $currentEntry
        CommandPath   = @($commandPath)
        LastPathIndex = $lastPathIndex
    }
}

function Get-ApmArgsAfterPath {
    param(
        [string[]]$ArgsBeforeCursor,
        [int]$LastPathIndex
    )

    if ($ArgsBeforeCursor.Count -eq 0) {
        return @()
    }

    if ($LastPathIndex -lt 0) {
        return $ArgsBeforeCursor
    }

    if ($LastPathIndex -ge ($ArgsBeforeCursor.Count - 1)) {
        return @()
    }

    @($ArgsBeforeCursor[($LastPathIndex + 1)..($ArgsBeforeCursor.Count - 1)])
}

function Get-ApmArgumentAnalysis {
    param(
        [string[]]$ArgsAfterPath,
        $Entry
    )

    $optionLookup = Get-ApmOptionLookup -Entry $Entry
    $positionals = [System.Collections.Generic.List[string]]::new()
    $pendingOption = $null
    $afterDoubleDash = $false

    foreach ($arg in $ArgsAfterPath) {
        if ($afterDoubleDash) {
            $positionals.Add($arg)
            continue
        }

        if ($arg -eq '--') {
            $afterDoubleDash = $true
            continue
        }

        if ($null -ne $pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($arg -match '^(?<option>-{1,2}[^=]+)=') {
            $optionName = $Matches.option
            if ($optionLookup.ContainsKey($optionName)) {
                continue
            }
        }

        if ($arg.StartsWith('-')) {
            if ($optionLookup.ContainsKey($arg) -and $optionLookup[$arg].ValueKind -ne 'flag') {
                $pendingOption = $arg
            }

            continue
        }

        $positionals.Add($arg)
    }

    [pscustomobject]@{
        Positionals     = @($positionals)
        PendingOption   = $pendingOption
        AfterDoubleDash = $afterDoubleDash
    }
}

function Get-ApmOptionValueResults {
    param(
        [string]$CommandKey,
        $Option,
        [string]$WordToComplete,
        [string]$AttachedPrefix = ''
    )

    switch ($Option.ValueKind) {
        'enum' {
            return @(Get-ApmClosedValueCompletions -Values $Option.Values -WordToComplete $WordToComplete -AttachedPrefix $AttachedPrefix)
        }
        'path' {
            $typedPath = if ([string]::IsNullOrEmpty($AttachedPrefix)) { $WordToComplete } else { $WordToComplete.Substring($AttachedPrefix.Length) }
            return @(Get-ApmPathCompletions -PathPrefix $typedPath -AttachedPrefix $AttachedPrefix)
        }
        'policy' {
            if ([string]::IsNullOrEmpty($AttachedPrefix) -and (Test-ApmPathLikeToken -Token $WordToComplete)) {
                return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<path>')
            }

            if (-not [string]::IsNullOrEmpty($AttachedPrefix)) {
                $typedPolicy = $WordToComplete.Substring($AttachedPrefix.Length)
                if (Test-ApmPathLikeToken -Token $typedPolicy) {
                    return @(Get-ApmPathCompletions -PathPrefix $typedPolicy -AttachedPrefix $AttachedPrefix -Placeholder '<path>')
                }
            }

            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('org', 'https://<url>', '<path>') -WordToComplete $WordToComplete -AttachedPrefix $AttachedPrefix)
        }
        'freeform' {
            return @(Get-ApmFreeformValueCompletions -SuggestedValues $Option.Values -WordToComplete $WordToComplete -AttachedPrefix $AttachedPrefix)
        }
        default {
            return @()
        }
    }
}

function Get-ApmPositionalResults {
    param(
        [string]$CommandKey,
        $Analysis,
        [string]$WordToComplete
    )

    $configKeys = (Get-Variable -Name ApmConfigKeyValues -Scope Script -ErrorAction SilentlyContinue).Value
    $booleanValues = (Get-Variable -Name ApmBooleanValues -Scope Script -ErrorAction SilentlyContinue).Value
    $runtimeValues = (Get-Variable -Name ApmRuntimeValues -Scope Script -ErrorAction SilentlyContinue).Value

    switch ($CommandKey) {
        'init' {
            if ($Analysis.Positionals.Count -eq 0) {
                if (Test-ApmPathLikeToken -Token $WordToComplete) {
                    return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<project-name>')
                }

                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('.', '<project-name>') -WordToComplete $WordToComplete)
            }
        }
        'install' {
            if (Test-ApmPathLikeToken -Token $WordToComplete) {
                return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<local-path>')
            }

            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<owner/repo>', 'https://<host>/<owner>/<repo>.git', './<local-path>', '<plugin@marketplace>') -WordToComplete $WordToComplete)
        }
        'uninstall' {
            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<owner/repo>', 'https://<host>/<owner>/<repo>.git', '<package>') -WordToComplete $WordToComplete)
        }
        'audit' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
            }
        }
        'unpack' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<bundle-path>')
            }
        }
        'view' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
            }

            if ($Analysis.Positionals.Count -eq 1) {
                return @(Get-ApmClosedValueCompletions -Values @('versions') -WordToComplete $WordToComplete)
            }
        }
        'info' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
            }

            if ($Analysis.Positionals.Count -eq 1) {
                return @(Get-ApmClosedValueCompletions -Values @('versions') -WordToComplete $WordToComplete)
            }
        }
        'deps info' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package-name>') -WordToComplete $WordToComplete)
            }
        }
        'deps update' {
            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
        }
        'mcp search' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<query>') -WordToComplete $WordToComplete)
            }
        }
        'mcp show' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<server-name>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace add' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<owner/repo>', '<host/owner/repo>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace browse' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<marketplace>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace update' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<marketplace>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace remove' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<marketplace>') -WordToComplete $WordToComplete)
            }
        }
        'search' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<query@marketplace>') -WordToComplete $WordToComplete)
            }
        }
        'run' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<script-name>') -WordToComplete $WordToComplete)
            }
        }
        'preview' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<script-name>') -WordToComplete $WordToComplete)
            }
        }
        'config get' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmClosedValueCompletions -Values $configKeys -WordToComplete $WordToComplete)
            }
        }
        'config set' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmClosedValueCompletions -Values $configKeys -WordToComplete $WordToComplete)
            }

            if ($Analysis.Positionals.Count -eq 1) {
                switch ($Analysis.Positionals[0]) {
                    'auto-integrate' {
                        return @(Get-ApmClosedValueCompletions -Values $booleanValues -WordToComplete $WordToComplete)
                    }
                    'temp-dir' {
                        return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<path>')
                    }
                }
            }
        }
        'runtime setup' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmClosedValueCompletions -Values $runtimeValues -WordToComplete $WordToComplete)
            }
        }
        'runtime remove' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmClosedValueCompletions -Values $runtimeValues -WordToComplete $WordToComplete)
            }
        }
    }

    @()
}

function Get-ApmUniqueResults {
    param([System.Collections.IEnumerable]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($result in $Results) {
        if ($null -eq $result) {
            continue
        }

        if ($seen.Add($result.CompletionText)) {
            $result
        }
    }
}

function Complete-Apm {
    param(
        [string]$WordToComplete,
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $null = Get-ApmCompletionCatalog

    $argsBeforeCursor = @(Get-ApmArgsBeforeCursor -CommandAst $CommandAst -WordToComplete $WordToComplete -CursorPosition $CursorPosition)
    $context = Get-ApmCommandContext -ArgsBeforeCursor $argsBeforeCursor
    $argsAfterPath = @(Get-ApmArgsAfterPath -ArgsBeforeCursor $argsBeforeCursor -LastPathIndex $context.LastPathIndex)
    $analysis = Get-ApmArgumentAnalysis -ArgsAfterPath $argsAfterPath -Entry $context.Entry
    $optionLookup = Get-ApmOptionLookup -Entry $context.Entry

    if ($WordToComplete -match '^(?<option>-{1,2}[^=]+)=(?<value>.*)$') {
        $optionName = $Matches.option
        if ($optionLookup.ContainsKey($optionName)) {
            $attachedPrefix = "$optionName="
            return Get-ApmUniqueResults (Get-ApmOptionValueResults -CommandKey $context.Key -Option $optionLookup[$optionName] -WordToComplete $WordToComplete -AttachedPrefix $attachedPrefix)
        }
    }

    if ($null -ne $analysis.PendingOption -and $optionLookup.ContainsKey($analysis.PendingOption)) {
        return Get-ApmUniqueResults (Get-ApmOptionValueResults -CommandKey $context.Key -Option $optionLookup[$analysis.PendingOption] -WordToComplete $WordToComplete)
    }

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    if ($WordToComplete.StartsWith('-')) {
        foreach ($option in $context.Entry.Options) {
            if (-not (Test-ApmStartsWith -Candidate $option.Token -Prefix $WordToComplete)) {
                continue
            }

            $results.Add((New-ApmCompletionResult -CompletionText $option.Token -ToolTip $option.Description -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName)))
        }

        return Get-ApmUniqueResults $results
    }

    if ($context.Entry.Subcommands.Count -gt 0 -and $analysis.Positionals.Count -eq 0 -and -not $analysis.AfterDoubleDash) {
        foreach ($subcommand in $context.Entry.Subcommands) {
            if (-not (Test-ApmStartsWith -Candidate $subcommand.Name -Prefix $WordToComplete)) {
                continue
            }

            $results.Add((New-ApmCompletionResult -CompletionText $subcommand.Name -ToolTip $subcommand.Description))
        }

        if (-not [string]::IsNullOrEmpty($WordToComplete)) {
            return Get-ApmUniqueResults $results
        }
    }

    if ([string]::IsNullOrEmpty($WordToComplete)) {
        foreach ($option in $context.Entry.Options) {
            $results.Add((New-ApmCompletionResult -CompletionText $option.Token -ToolTip $option.Description -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName)))
        }
    }

    foreach ($positionalResult in Get-ApmPositionalResults -CommandKey $context.Key -Analysis $analysis -WordToComplete $WordToComplete) {
        $results.Add($positionalResult)
    }

    Get-ApmUniqueResults $results
}

Register-ArgumentCompleter -Native -CommandName @('apm', 'apm.exe') -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    Complete-Apm -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}

<#
.SYNOPSIS
Registers native PowerShell completion for apm and apm.exe.

.DESCRIPTION
The completer is static-first and is derived from the official APM CLI
reference plus the upstream microsoft/apm click command definitions for
documented enum values and aliases. When apm is installed, each command's
live '--help' page is parsed once per session and merged over the static
table, so subcommands and options added by newer releases still complete.
#>

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name ApmLiveHelpCache -Scope Script -ErrorAction Ignore)) {
    $script:ApmLiveHelpCache = @{
        ExecutableProbed = $false
        Executable       = $null
        Stamp            = $null
        Entries          = @{}
    }
}

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

function Get-ApmListValueCompletion {
    # Completes the segment after the last comma of a comma-separated value.
    # PowerShell parses an unquoted a,b,c as an array literal: $WordToComplete
    # is then only the last segment and only that segment is replaced, while
    # the native command still receives 'a,b,c' as one argument. A quoted word
    # arrives whole with its opening quote, so the earlier segments and the
    # quote are kept as the prefix.
    param(
        [string[]]$Values,
        [string]$WordToComplete,
        [string]$AttachedPrefix = '',
        [string]$ElementText = ''
    )

    $quote = ''
    $word = $WordToComplete
    if ($word.Length -gt 0 -and ($word[0] -eq "'" -or $word[0] -eq '"')) {
        # PowerShell closes an unterminated quote in $WordToComplete itself.
        $quote = [string]$word[0]
        $word = $word.Substring(1)
        if ($word.EndsWith($quote)) {
            $word = $word.Substring(0, $word.Length - 1)
        }
    }

    $emitPrefix = ''
    if (-not [string]::IsNullOrEmpty($AttachedPrefix) -and $word.StartsWith($AttachedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $emitPrefix = $word.Substring(0, $AttachedPrefix.Length)
        $word = $word.Substring($AttachedPrefix.Length)
    }

    $lastComma = $word.LastIndexOf(',')
    $committed = $word.Substring(0, $lastComma + 1)
    $fragment = $word.Substring($lastComma + 1)

    $source = if ([string]::IsNullOrEmpty($ElementText)) { $WordToComplete } else { $ElementText }
    $source = $source -replace '^[''"]', '' -replace '^-{1,2}[^=,]+=', ''
    $chosen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($segment in @($source -split ',' | Select-Object -SkipLast 1)) {
        [void]$chosen.Add($segment.Trim())
    }

    foreach ($value in $Values) {
        if ($chosen.Contains($value) -or -not (Test-ApmStartsWith -Candidate $value -Prefix $fragment)) {
            continue
        }

        New-ApmCompletionResult -CompletionText "$quote$emitPrefix$committed$value$quote" -ToolTip $value
    }
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
            [string[]]$Values = @(),
            [switch]$OptionalValue
        )

        foreach ($token in $Tokens) {
            [pscustomobject]@{
                Token         = $token
                Description   = $Description
                ValueKind     = $ValueKind
                Values        = @($Values)
                OptionalValue = [bool]$OptionalValue
            }
        }
    }

    # apm 0.33.0: --target and --runtime share one 21-entry harness list.
    $targetValues = @(
        'agent-skills', 'agents', 'agy', 'all', 'antigravity', 'claude', 'codex', 'copilot',
        'copilot-app', 'copilot-cowork', 'cursor', 'gemini', 'grok-build', 'grok-cloud',
        'hermes', 'intellij', 'kiro', 'openclaw', 'opencode', 'vscode', 'windsurf'
    )
    $installRuntimeValues = $targetValues
    $auditFormatValues = @('text', 'json', 'sarif', 'markdown')
    $configKeyValues = @('auto-integrate', 'temp-dir')
    $booleanValues = @('true', 'false', 'yes', 'no', '1', '0')
    $runtimeValues = @('copilot', 'codex', 'gemini', 'llm')
    $countValues = @('0', '1', '4', '8', '10', '20', '50')
    $transportValues = @('stdio', 'http', 'sse', 'streamable-http')
    $packFormatValues = @('plugin', 'agent-plugin', 'claude', 'claude-plugin', 'apm')
    $packMarketplaceValues = @('all', 'none', 'claude', 'codex')
    $lifecycleEventValues = @('pre-install', 'post-install', 'pre-update', 'post-update', 'pre-uninstall', 'post-uninstall')

    $catalog = [ordered]@{}

    $catalog[''] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'init' 'Initialize new APM project'
            & $newCommand 'install' 'Install APM, MCP, and LSP dependencies'
            & $newCommand 'uninstall' 'Remove packages using manifest entries or direct locked refs'
            & $newCommand 'prune' 'Remove APM packages absent from the resolved dependency set'
            & $newCommand 'audit' 'Scan installed primitives for hidden Unicode, drift, and lockfile issues'
            & $newCommand 'auth' 'Get a working credential for a git host'
            & $newCommand 'pack' 'Pack distributable artifacts from your APM project'
            & $newCommand 'unpack' '[Deprecated] Extract an APM bundle into the current project'
            & $newCommand 'update' 'Refresh APM dependencies to the latest matching refs'
            & $newCommand 'self-update' 'Update the APM CLI binary itself to the latest version'
            & $newCommand 'view' 'View package metadata or list remote versions'
            & $newCommand 'outdated' 'Show outdated locked dependencies'
            & $newCommand 'deps' 'Manage APM package dependencies'
            & $newCommand 'mcp' 'Discover, inspect, and install MCP servers'
            & $newCommand 'marketplace' 'Manage marketplaces for discovery and governance'
            & $newCommand 'search' 'Search plugins in a marketplace (QUERY@MARKETPLACE)'
            & $newCommand 'run' 'Run a script with parameters (experimental)'
            & $newCommand 'preview' 'Preview a script''s compiled prompt files'
            & $newCommand 'list' 'List available scripts in the current project'
            & $newCommand 'compile' 'Compile APM context into distributed AGENTS.md files'
            & $newCommand 'config' 'Configure APM CLI'
            & $newCommand 'runtime' 'Manage AI runtimes (experimental)'
            & $newCommand 'approve' 'Approve package executables'
            & $newCommand 'deny' 'Deny package executables'
            & $newCommand 'cache' 'Manage the local package cache'
            & $newCommand 'doctor' 'Run environment diagnostics (git, network, auth, marketplace config)'
            & $newCommand 'experimental' 'Manage experimental feature flags'
            & $newCommand 'find' 'Find which package owns a file path'
            & $newCommand 'lifecycle' 'Inspect, test, and scaffold lifecycle scripts'
            & $newCommand 'lock' 'Resolve dependencies and write apm.lock.yaml without deploying'
            & $newCommand 'plugin' 'Scaffold and manage plugins (plugin-author workflows)'
            & $newCommand 'policy' 'Inspect and diagnose APM policy'
            & $newCommand 'publish' 'Publish a package to a registry'
            & $newCommand 'targets' 'Show resolved targets for the current project'
            & $newCommand 'info' 'Hidden alias for view'
        )
        Options = @(
            & $newOption @('--version') 'Show version and exit'
            & $newOption @('--verbose', '-v') 'Enable debug-level logging'
            & $newOption @('--help') 'Show help message and exit'
        )
    }

    $catalog['approve'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--pending') 'List packages with unapproved executables'
            & $newOption @('--all') 'Approve every package with executables'
            & $newOption @('--recommended') 'Approve the org-recommended executable set'
            & $newOption @('--list') 'List effective trust decisions'
            & $newOption @('--user') 'Persist to your personal ~/.apm/config.json instead of apm.yml'
        )
    }

    $catalog['deny'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--user') 'Record the deny in your personal ~/.apm/config.json instead of apm.yml'
        )
    }

    $catalog['auth'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--check') 'Validate the token against the host''s REST API (one network call)'
            & $newOption @('--export') 'Print "export VAR=token" on stdout for eval'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['cache'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'clean' 'Remove all cached content'
            & $newCommand 'info' 'Show cache location and size statistics'
            & $newCommand 'prune' 'Remove Git checkout SHA groups older than N days'
        )
        Options = @()
    }

    $catalog['cache clean'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--force', '-f') 'Skip confirmation prompt'
            & $newOption @('--yes', '-y') 'Skip confirmation prompt'
        )
    }

    $catalog['cache info'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['cache prune'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--days') 'Remove SHA groups not accessed within this many days' 'freeform' @('7', '30', '90')
        )
    }

    $catalog['doctor'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['experimental'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'disable' 'Disable an experimental feature'
            & $newCommand 'enable' 'Enable an experimental feature'
            & $newCommand 'list' 'List all experimental features'
            & $newCommand 'reset' 'Reset experimental features to defaults'
        )
        Options = @(
            & $newOption @('--verbose', '-v') 'Show verbose output'
        )
    }

    $catalog['experimental disable'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['experimental enable'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['experimental list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--enabled') 'Show only enabled features'
            & $newOption @('--disabled') 'Show only disabled features'
            & $newOption @('--verbose', '-v') 'Show detailed output'
            & $newOption @('--json') 'Output as JSON array'
        )
    }

    $catalog['experimental reset'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '-y') 'Skip confirmation prompt'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['find'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--source') 'Append resolved origin (oci/git/local) to each package name'
            & $newOption @('--path') 'Print full root-to-target dependency chain (like apm deps why)'
        )
    }

    $catalog['lifecycle'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'init' 'Inject a starter lifecycle: block into apm.yml'
            & $newCommand 'test' 'Dry-run a synthetic lifecycle event through discovered scripts'
            & $newCommand 'trust' 'Trust the project apm.yml lifecycle: block so its scripts run'
            & $newCommand 'untrust' 'Revoke trust for the project apm.yml lifecycle: block'
            & $newCommand 'validate' 'Validate all discovered script files for errors'
        )
        Options = @()
    }

    $catalog['lifecycle init'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--force') 'Overwrite existing lifecycle: block if present'
        )
    }

    $catalog['lifecycle test'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
            & $newOption @('--execute') 'Actually run the scripts (default is a non-executing dry-run)'
        )
    }

    $catalog['lifecycle trust'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['lifecycle untrust'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['lifecycle validate'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['lock'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'export' 'Export an SBOM/inventory from the existing lockfile'
        )
        Options = @(
            & $newOption @('--verbose', '-v') 'Show per-dependency resolution details'
            & $newOption @('--global', '-g') 'Operate on ~/.apm/apm.yml instead of the current project'
            & $newOption @('--update') 'Re-resolve refs to their latest SHAs before writing the lockfile'
            & $newOption @('--no-policy') 'Skip policy enforcement during resolution'
            & $newOption @('--target', '-t') 'Agent target(s) to scope policy enforcement during resolution' 'list' $targetValues
            & $newOption @('--parallel-downloads') 'Max concurrent package downloads (0 to disable parallelism)' 'freeform' $countValues
        )
    }

    $catalog['lock export'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--format', '-f') 'SBOM output format' 'enum' @('cyclonedx', 'spdx')
            & $newOption @('--output', '-o') 'Write the SBOM to a file instead of stdout' 'path'
            & $newOption @('--global', '-g') 'Read the user-scope (~/.apm/) lockfile'
            & $newOption @('--timestamp') 'Pin the SBOM timestamp (ISO 8601)' 'freeform' @('<iso-8601>')
        )
    }

    $catalog['plugin'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'init' 'Scaffold a plugin project (creates plugin.json + apm.yml)'
        )
        Options = @()
    }

    $catalog['plugin init'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '-y') 'Skip interactive prompts and use auto-detected defaults'
            & $newOption @('--target') 'Comma-separated target list (skip prompt)' 'list' $targetValues
            & $newOption @('--format') 'Plugin layout' 'enum' @('plugin', 'agent-plugin', 'claude', 'claude-plugin')
            & $newOption @('--claude-plugin') 'Scaffold the legacy Claude-compatible layout'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['policy'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'explain' 'Explain the effective executable-trust decision for a package'
            & $newCommand 'status' 'Show the current policy posture (discovery, cache, rules)'
        )
        Options = @()
    }

    $catalog['policy explain'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['policy status'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--policy-source') 'Override discovery (org, URL, or path)' 'policy'
            & $newOption @('--no-cache') 'Force a fresh fetch (skip the policy cache)'
            & $newOption @('--json') 'Emit the report as JSON (alias of -o json)'
            & $newOption @('--output', '-o') 'Output format' 'enum' @('table', 'json')
            & $newOption @('--check') 'Exit non-zero (1) when no usable policy is found'
        )
    }

    $catalog['publish'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--registry') 'Registry name (from apm.yml registries: block)' 'freeform' @('<registry>')
            & $newOption @('--package') 'Package identity to publish as (owner/repo)' 'freeform' @('<owner/repo>')
            & $newOption @('--zip') 'Path to a pre-built .zip archive (skips the pack step)' 'path'
            & $newOption @('--dry-run') 'Preview without uploading'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['targets'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--json') 'Output as JSON instead of a table'
            & $newOption @('--all') 'Include the agent-skills meta-target in JSON output'
        )
    }

    $catalog['init'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--discover') 'Inventory existing local packages without writes'
            & $newOption @('--apply', '--write') 'Add existing local package references to consumer apm.yml; never install'
            & $newOption @('--format') 'Discovery report format' 'enum' @('text', 'json', 'yaml')
            & $newOption @('--global', '-g') 'Discover under home and declare packages in ~/.apm/apm.yml'
            & $newOption @('--yes', '-y') 'Skip interactive prompts and use auto-detected defaults'
            & $newOption @('--plugin') 'Initialize as a plugin authoring project'
            & $newOption @('--marketplace') '(deprecated) Use apm marketplace init instead'
            & $newOption @('--target') 'Comma-separated target list (skip prompt, write directly)' 'list' $targetValues
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['install'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--runtime') 'Target specific runtime only' 'enum' $installRuntimeValues
            & $newOption @('--exclude') 'Exclude specific runtime from installation' 'enum' $installRuntimeValues
            & $newOption @('--only') 'Install only specific dependency type' 'enum' @('apm', 'mcp')
            & $newOption @('--target', '-t') 'Target harness(es) to deploy to (comma-separated)' 'list' $targetValues
            & $newOption @('--update') 'Update dependencies to latest Git references'
            & $newOption @('--force') 'Overwrite locally-authored files on collision'
            & $newOption @('--dry-run') 'Show what would be installed without installing'
            & $newOption @('--frozen') 'Refuse to install when apm.lock.yaml is missing or out of sync (CI-safe)'
            & $newOption @('--parallel-downloads') 'Max concurrent package downloads' 'freeform' $countValues
            & $newOption @('--verbose', '-v') 'Show detailed installation information'
            & $newOption @('--trust-transitive-mcp') 'Trust self-defined MCP servers from transitive packages'
            & $newOption @('--dev') 'Install as development dependency'
            & $newOption @('--allow-insecure') 'Allow HTTP (insecure) dependencies'
            & $newOption @('--allow-insecure-host') 'Allow transitive HTTP dependencies from this hostname (repeatable)' 'freeform' @('<hostname>')
            & $newOption @('--global', '-g') 'Install to user scope instead of the current project'
            & $newOption @('--ssh') 'Prefer SSH transport for shorthand (owner/repo) dependencies'
            & $newOption @('--https') 'Prefer HTTPS transport for shorthand (owner/repo) dependencies'
            & $newOption @('--allow-protocol-fallback') 'Restore the legacy permissive cross-protocol fallback chain'
            & $newOption @('--mcp') 'Add an MCP server entry to apm.yml' 'freeform' @('<name>')
            & $newOption @('--transport') 'MCP transport for --mcp entries' 'enum' $transportValues
            & $newOption @('--url') 'MCP server URL for remote transports (requires --mcp)' 'freeform' @('https://<host>/mcp')
            & $newOption @('--env') 'Environment variable for stdio MCP, repeatable (requires --mcp)' 'freeform' @('<KEY=VALUE>')
            & $newOption @('--header') 'HTTP header for remote MCP, repeatable (requires --mcp and --url)' 'freeform' @('<KEY=VALUE>')
            & $newOption @('--mcp-version') 'Pin MCP registry entry to a specific version (requires --mcp)' 'freeform' @('<version>')
            & $newOption @('--registry') 'MCP registry URL for resolving --mcp NAME' 'freeform' @('https://<registry>')
            & $newOption @('--skill') 'Install only named skill(s) from a SKILL_BUNDLE (repeatable)' 'freeform' @('<name>')
            & $newOption @('--no-policy') 'Skip org policy enforcement for this invocation'
            & $newOption @('--audit') 'Run apm audit over deployed files during install' 'enum' @('off', 'warn', 'block')
            & $newOption @('--no-audit') 'Disable the install-time audit for this invocation'
            & $newOption @('--refresh') 'Re-fetch all dependencies from upstream and re-resolve all ref pins'
            & $newOption @('--legacy-skill-paths') 'Deploy skill files to per-client paths instead of .agents/skills/'
            & $newOption @('--as') 'Override the display label when installing a local bundle' 'freeform' @('<alias>')
            & $newOption @('--trust-bin') 'Deploy bin/ executables for this invocation'
            & $newOption @('--no-trust-bin') 'Skip bin/ executable deployment for this invocation'
            & $newOption @('--root') 'Install into DIR instead of the current directory' 'path'
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
            & $newOption @('--no-policy') 'Skip org policy discovery and enforcement'
            & $newOption @('--no-fail-fast') 'Run all checks even after a failure'
            & $newOption @('--no-drift') 'Skip the install-replay drift check'
            & $newOption @('--external') 'Ingest findings from an external SARIF-native scanner (repeatable)' 'enum' @('skillspector', 'sarif')
            & $newOption @('--external-sarif') 'SARIF file to ingest for --external sarif' 'path'
            & $newOption @('--external-llm') 'Force LLM-powered analysis on for external scanners'
            & $newOption @('--no-external-llm') 'Force LLM-powered analysis off for external scanners'
            & $newOption @('--external-args') 'Extra argv tokens for external scanners this run' 'freeform' @('<args>')
        )
    }

    $catalog['pack'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--output', '-o') 'Output directory' 'path'
            & $newOption @('--target', '-t') 'Filter files by target' 'enum' $targetValues
            & $newOption @('--archive') 'Produce an archive (.zip by default) instead of a directory'
            & $newOption @('--archive-format') 'Archive format when --archive is set' 'enum' @('zip', 'tar.gz')
            & $newOption @('--dry-run') 'List files that would be packed without writing anything'
            & $newOption @('--format') 'Bundle format' 'enum' $packFormatValues
            & $newOption @('--claude-plugin') 'Select the legacy Claude plugin bundle output'
            & $newOption @('--force') 'On collision, last writer wins instead of first'
            & $newOption @('--verbose', '-v') 'Show detailed packing information'
            & $newOption @('--offline') 'Marketplace: use cached refs, skip network'
            & $newOption @('--include-prerelease') 'Marketplace: include pre-release version tags'
            & $newOption @('--check-versions') 'Release gate: verify per-package versions agree with the versioning strategy'
            & $newOption @('--check-clean') 'Release gate: diff regenerated marketplace outputs against disk'
            & $newOption @('--strict-metadata') 'Marketplace: fail when remote metadata cannot be fetched'
            & $newOption @('--marketplace', '-m') 'Comma-separated marketplace outputs to build' 'list' $packMarketplaceValues
            & $newOption @('--marketplace-path') 'Override output path for a format (repeatable)' 'freeform' @('<FORMAT=PATH>')
            & $newOption @('--json') 'Emit machine-readable JSON to stdout'
            & $newOption @('--legacy-skill-paths') 'Deploy skill files to per-client paths instead of .agents/skills/'
        )
    }

    $catalog['unpack'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--output', '-o') 'Target project directory' 'path'
            & $newOption @('--skip-verify') 'Skip completeness verification against the bundle lockfile'
            & $newOption @('--force') 'Deploy despite critical hidden-character findings'
            & $newOption @('--dry-run') 'Show what would be extracted without writing anything'
            & $newOption @('--verbose', '-v') 'Show detailed unpacking information'
        )
    }

    $catalog['update'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '-y') 'Skip the confirmation prompt (for CI / automation)'
            & $newOption @('--dry-run') 'Render the update plan and exit without changing anything'
            & $newOption @('--verbose', '-v') 'Show unchanged deps and detailed pipeline diagnostics'
            & $newOption @('--global', '-g') 'Refresh user-scope dependencies (~/.apm/) instead of the current project'
            & $newOption @('--force') 'Overwrite locally-authored files and deploy despite critical security findings'
            & $newOption @('--parallel-downloads') 'Max concurrent package downloads (0 to disable parallelism)' 'freeform' $countValues
            & $newOption @('--target', '-t') 'Agent target(s) to update for (comma-separated for multiple)' 'list' $targetValues
        )
    }

    $catalog['self-update'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--check') 'Only check for updates without installing'
        )
    }

    $catalog['view'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Inspect package from user scope'
            & $newOption @('--registry') 'List versions from a registry (name one, or a full git URL)' 'freeform' @('<registry>') -OptionalValue
        )
    }

    $catalog['info'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Inspect package from user scope'
            & $newOption @('--registry') 'List versions from a registry (name one, or a full git URL)' 'freeform' @('<registry>') -OptionalValue
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
            & $newCommand 'update' 'DEPRECATED: use apm update instead (strict superset)'
            & $newCommand 'why' 'Explain why a package is installed by walking the lockfile back to its roots'
        )
        Options = @()
    }

    $catalog['deps why'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Resolve against the user-scope lockfile'
            & $newOption @('--json') 'Emit machine-readable JSON to stdout'
        )
    }

    $catalog['deps list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'List user-scope packages instead of the current project'
            & $newOption @('--all') 'List packages from both project and user scope'
            & $newOption @('--insecure') 'Show only installed dependencies locked to http:// sources'
        )
    }

    $catalog['deps tree'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--global', '-g') 'Show user-scope dependency tree (~/.apm/)'
        )
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
            & $newOption @('--target', '-t') 'Force deployment to a specific target (comma-separated)' 'list' $targetValues
            & $newOption @('--parallel-downloads') 'Max concurrent downloads' 'freeform' $countValues
            & $newOption @('--legacy-skill-paths') 'Deploy skill files to per-client paths instead of .agents/skills/'
        )
    }

    $catalog['mcp'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'install' 'Add an MCP server to apm.yml'
            & $newCommand 'list' 'List MCP servers'
            & $newCommand 'search' 'Search MCP servers'
            & $newCommand 'show' 'Show MCP server details'
        )
        Options = @()
    }

    $catalog['mcp install'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--transport') 'MCP transport' 'enum' $transportValues
            & $newOption @('--url') 'Server URL for remote transports' 'freeform' @('https://<host>/mcp')
            & $newOption @('--env') 'Environment variable (repeatable)' 'freeform' @('<KEY=VALUE>')
            & $newOption @('--header') 'HTTP header (repeatable)' 'freeform' @('<KEY=VALUE>')
            & $newOption @('--target', '-t') 'Agent target(s) to deploy to' 'list' $targetValues
            & $newOption @('--registry') 'Custom registry URL' 'freeform' @('https://<registry>')
            & $newOption @('--mcp-version') 'Pin registry entry to a specific version' 'freeform' @('<version>')
            & $newOption @('--global', '-g') 'Install to user scope (~/.apm/)'
            & $newOption @('--trust-transitive-mcp') 'Trust MCP servers from transitive dependencies'
            & $newOption @('--dev') 'Install as development dependency'
            & $newOption @('--dry-run') 'Show what would change without writing files'
            & $newOption @('--force') 'Overwrite locally-authored files on collision'
            & $newOption @('--verbose') 'Show detailed output'
            & $newOption @('--no-policy') 'Skip org policy enforcement'
        )
    }

    $catalog['mcp list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--limit') 'Number of results to show' 'freeform' @('20', '50')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['mcp search'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--limit') 'Number of results to show' 'freeform' @('5', '10', '20', '50')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['mcp show'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'add' 'Register a marketplace'
            & $newCommand 'list' 'List registered marketplaces'
            & $newCommand 'browse' 'Browse marketplace plugins'
            & $newCommand 'update' 'Refresh marketplace cache'
            & $newCommand 'remove' 'Remove a registered marketplace'
            & $newCommand 'validate' 'Validate marketplace structure and plugin schema'
            & $newCommand 'init' 'Add a marketplace: block to apm.yml'
            & $newCommand 'check' 'Validate marketplace entries are resolvable'
            & $newCommand 'outdated' 'Show packages with available upgrades'
            & $newCommand 'audit' 'Check that plugin dependencies resolve through the marketplace'
            & $newCommand 'package' 'Manage packages in marketplace authoring config'
            & $newCommand 'migrate' 'Fold marketplace.yml into apm.yml''s marketplace: block'
        )
        Options = @()
    }

    $catalog['marketplace add'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--name', '-n') 'Display name (defaults to repo name)' 'freeform' @('<marketplace-name>')
            & $newOption @('--ref', '-r') 'Git ref (branch, tag, or commit). Default: main' 'freeform' @('<ref>')
            & $newOption @('--host') 'Git host FQDN for OWNER/REPO shorthand' 'freeform' @('<host>')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace validate'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace init'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--force') 'Overwrite an existing marketplace: block in apm.yml'
            & $newOption @('--no-gitignore-check') 'Skip the .gitignore staleness check'
            & $newOption @('--name') 'Marketplace/package name (default: my-marketplace)' 'freeform' @('<name>')
            & $newOption @('--owner') 'Owner name for the marketplace' 'freeform' @('<owner>')
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace check'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--offline') 'Schema + cached-ref checks only (no network)'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace outdated'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--offline') 'Use cached refs only (no network)'
            & $newOption @('--include-prerelease') 'Include prerelease versions'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace audit'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--strict') 'Exit non-zero on bypasses, fetch errors, or no verified packages'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace package'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'add' 'Add a package to marketplace authoring config'
            & $newCommand 'remove' 'Remove a package from marketplace authoring config'
            & $newCommand 'set' 'Update a package entry in marketplace authoring config'
        )
        Options = @()
    }

    $catalog['marketplace package add'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--name') 'Package name (default: repo name)' 'freeform' @('<name>')
            & $newOption @('--version') 'Semver range (e.g. >=1.0.0)' 'freeform' @('<range>')
            & $newOption @('--ref') 'Pin to a git ref (SHA, tag, or HEAD)' 'freeform' @('<ref>')
            & $newOption @('--subdir', '-s') 'Subdirectory inside source repo' 'freeform' @('<subdir>')
            & $newOption @('--tag-pattern') 'Tag pattern (e.g. v{version})' 'freeform' @('v{version}')
            & $newOption @('--tags') 'Comma-separated tags' 'freeform' @('<tags>')
            & $newOption @('--include-prerelease') 'Include prerelease versions'
            & $newOption @('--no-verify') 'Skip remote reachability check'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace package remove'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '-y') 'Skip confirmation prompt'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace package set'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--version') 'Semver range (e.g. >=1.0.0)' 'freeform' @('<range>')
            & $newOption @('--ref') 'Pin to a git ref (SHA, tag, or HEAD)' 'freeform' @('<ref>')
            & $newOption @('--subdir') 'Subdirectory inside source repo' 'freeform' @('<subdir>')
            & $newOption @('--tag-pattern') 'Tag pattern (e.g. v{version})' 'freeform' @('v{version}')
            & $newOption @('--tags') 'Comma-separated tags' 'freeform' @('<tags>')
            & $newOption @('--include-prerelease') 'Include prerelease versions'
            & $newOption @('--verbose', '-v') 'Show detailed output'
        )
    }

    $catalog['marketplace migrate'] = [pscustomobject]@{
        Subcommands = @()
        Options = @(
            & $newOption @('--yes', '--force', '-y') 'Overwrite an existing marketplace: block in apm.yml'
            & $newOption @('--dry-run') 'Show the proposed apm.yml changes without writing them'
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
            & $newOption @('--target', '-t') 'Target agent format (comma-separated)' 'list' $targetValues
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
            & $newOption @('--legacy-skill-paths') 'Deploy skill files to per-client paths instead of .agents/skills/'
            & $newOption @('--all') 'Compile for all canonical targets'
            & $newOption @('--force-instructions') 'Include the instructions section even when rules are already populated'
            & $newOption @('--no-force-instructions') 'Keep the default instructions deduplication'
            & $newOption @('--root') 'Write AGENTS.md / CLAUDE.md outputs under DIR' 'path'
            & $newOption @('--global', '-g') 'Compile user-scope root context files from ~/.apm/apm_modules'
        )
    }

    $catalog['config'] = [pscustomobject]@{
        Subcommands = @(
            & $newCommand 'get' 'Get a configuration value'
            & $newCommand 'list' 'List all configuration values'
            & $newCommand 'set' 'Set a configuration value'
            & $newCommand 'unset' 'Unset a configuration value'
        )
        Options = @()
    }

    $catalog['config get'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['config list'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['config set'] = [pscustomobject]@{
        Subcommands = @()
        Options = @()
    }

    $catalog['config unset'] = [pscustomobject]@{
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
            & $newOption @('--yes', '-y') 'Confirm the action without prompting'
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
    $script:ApmLifecycleEventValues = $lifecycleEventValues

    $script:ApmCompletionCatalog
}

function Get-ApmLiveHelpStamp {
    # Identifies the installed binary; a changed stamp (upgrade, reinstall,
    # removal) drops every parsed help page. The WinGet shim is a symlink, so
    # the stamp follows it to the real executable.
    $cache = $script:ApmLiveHelpCache
    if (-not $cache.ExecutableProbed) {
        $cache.ExecutableProbed = $true
        $command = Get-Command -Name 'apm.exe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($null -ne $command) {
            $cache.Executable = $command.Source
        }
    }

    if ([string]::IsNullOrEmpty($cache.Executable)) {
        return $null
    }

    $file = [System.IO.FileInfo]::new($cache.Executable)
    $target = $file.ResolveLinkTarget($true)
    if ($null -ne $target) {
        $file = $target
    }

    if (-not $file.Exists) {
        return $null
    }

    "$($file.FullName)|$($file.LastWriteTimeUtc.Ticks)"
}

function Invoke-ApmHelpCapture {
    param([string[]]$CommandPath)

    # APM_E2E_TESTS=1 skips the update check (a GitHub API call plus a cache
    # file write) that apm's root callback runs before a subcommand's --help.
    $process = [System.Diagnostics.Process]::new()
    try {
        $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new($script:ApmLiveHelpCache.Executable)
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.Environment['APM_E2E_TESTS'] = '1'
        $process.StartInfo.Environment['PYTHONIOENCODING'] = 'utf-8'
        foreach ($segment in @($CommandPath)) {
            $process.StartInfo.ArgumentList.Add($segment)
        }
        $process.StartInfo.ArgumentList.Add('--help')

        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit(5000)) {
            try { $process.Kill($true) } catch { Write-Verbose "apm --help did not exit in 5 s and could not be killed: $_" }
            return $null
        }

        if ($process.ExitCode -ne 0) {
            return $null
        }

        $stdout.GetAwaiter().GetResult() -replace '\e\[[0-9;?]*[ -/]*[@-~]', ''
    }
    catch {
        $null
    }
    finally {
        $process.Dispose()
    }
}

function ConvertTo-ApmLiveOption {
    param(
        [string[]]$Tokens,
        [string]$Metavar,
        [string]$Description
    )

    $valueKind = 'freeform'
    $values = @()
    $listedValues = @(
        if ($Description -match '(?:Values|Names):\s*(?<values>[a-z0-9][a-z0-9-]*(?:,\s*[a-z0-9][a-z0-9-]*)*)') {
            $Matches['values'] -split ',\s*'
        }
    )

    if ([string]::IsNullOrEmpty($Metavar)) {
        $valueKind = 'flag'
    }
    elseif ($Metavar -match '^\[(?<choices>[^\]]+\|[^\]]+)\]$') {
        $valueKind = 'enum'
        $values = @($Matches['choices'] -split '\|')
    }
    elseif ($Metavar -ceq 'TARGET' -or $Description -match '(?i)\bcomma(?:s|-separated)\b') {
        $valueKind = 'list'
        $values = @(if ($listedValues.Count -gt 0) { $listedValues } elseif ($Metavar -ceq 'TARGET') { $script:ApmTargetValues })
    }
    elseif ($listedValues.Count -gt 0) {
        $valueKind = 'enum'
        $values = $listedValues
    }
    elseif ($Metavar -cin @('PATH', 'DIR', 'FILE', 'DIRECTORY')) {
        $valueKind = 'path'
    }
    else {
        $values = @('<' + $Metavar.Trim([char[]]'[]').ToLowerInvariant() + '>')
    }

    $toolTip = ($Description -replace '\s*\[default: [^\]]*\]', '').Trim()
    foreach ($token in $Tokens) {
        [pscustomobject]@{
            Token         = $token
            Description   = $toolTip
            ValueKind     = $valueKind
            Values        = $values
            OptionalValue = $Metavar -match '^\[[^\]|]+\]$'
        }
    }
}

function ConvertFrom-ApmHelpText {
    # Parses Click help: the 'Options:' block and every '... commands:' block.
    # A blank line ends a block, so epilog examples are never read as entries.
    param([string]$Text)

    $subcommands = [System.Collections.Generic.List[object]]::new()
    $options = [System.Collections.Generic.List[object]]::new()
    $section = ''
    $pending = $null

    foreach ($line in ($Text -split '\r?\n')) {
        $isOptionLine = $section -eq 'options' -and $line -match '^  (?<spec>-.+?)(?:\s{2,}(?<desc>\S.*))?$'
        $spec = if ($isOptionLine) { $Matches['spec'] } else { '' }
        $description = if ($isOptionLine) { [string]$Matches['desc'] } else { '' }
        if ($isOptionLine -or [string]::IsNullOrWhiteSpace($line) -or $line -match '^[A-Za-z][A-Za-z ]*:\s*$') {
            if ($null -ne $pending) {
                foreach ($option in ConvertTo-ApmLiveOption -Tokens $pending.Tokens -Metavar $pending.Metavar -Description $pending.Description) {
                    $options.Add($option)
                }
                $pending = $null
            }
        }

        if ($isOptionLine) {
            if ($spec -match'^(?<tokens>-[^\s,/]+(?:(?:,\s*|\s+/\s+)-[^\s,/]+)*)(?:\s+(?<metavar>\S.*))?$') {
                $pending = [pscustomobject]@{
                    Tokens      = @($Matches['tokens'] -split ',\s*|\s+/\s+')
                    Metavar     = [string]$Matches['metavar']
                    Description = $description
                }
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            $section = ''
            continue
        }

        if ($line -match '^(?<name>[A-Za-z][A-Za-z ]*):\s*$') {
            $section = if ($Matches['name'] -ceq 'Options') { 'options' } elseif ($Matches['name'] -match '(?i)commands$') { 'commands' } else { '' }
            continue
        }

        if ($section -eq 'commands' -and $line -match '^  (?<name>[a-z][a-z0-9-]*)(?:\s{2,}(?<desc>\S.*))?$') {
            $subcommands.Add([pscustomobject]@{ Name = $Matches['name']; Description = [string]$Matches['desc'] })
            continue
        }

        if ($null -ne $pending -and $line -match '^\s{3,}(?<more>\S.*)$') {
            # Click wraps hyphenated words at the hyphen ('grok-' / 'cloud').
            $more = $Matches['more']
            $pending.Description = if ([string]::IsNullOrEmpty($pending.Description)) {
                $more
            }
            elseif ($pending.Description -match '[a-z]-$') {
                "$($pending.Description)$more"
            }
            else {
                "$($pending.Description) $more"
            }
        }
    }

    [pscustomobject]@{
        Subcommands = @($subcommands)
        Options     = @($options)
    }
}

function Get-ApmCatalogEntry {
    # The static entry for a command path with the live '--help' page merged
    # over it: static definitions win (they carry richer value kinds), live
    # subcommands and options the table lacks are appended.
    param([string]$Key)

    $catalog = Get-ApmCompletionCatalog
    $staticEntry = if ($catalog.Contains($Key)) {
        $catalog[$Key]
    }
    else {
        [pscustomobject]@{ Subcommands = @(); Options = @() }
    }

    $cache = $script:ApmLiveHelpCache
    $stamp = Get-ApmLiveHelpStamp
    if ($null -eq $stamp) {
        return $staticEntry
    }

    if ($cache.Stamp -ne $stamp) {
        $cache.Stamp = $stamp
        $cache.Entries = @{}
    }

    if ($cache.Entries.ContainsKey($Key)) {
        return $cache.Entries[$Key]
    }

    $helpText = Invoke-ApmHelpCapture -CommandPath @($Key -split ' ' | Where-Object { $_ })
    if ([string]::IsNullOrEmpty($helpText)) {
        $cache.Entries[$Key] = $staticEntry
        return $staticEntry
    }

    $live = ConvertFrom-ApmHelpText -Text $helpText
    $subcommandNames = [System.Collections.Generic.HashSet[string]]::new([string[]]@($staticEntry.Subcommands | ForEach-Object { $_.Name }), [System.StringComparer]::Ordinal)
    $optionTokens = [System.Collections.Generic.HashSet[string]]::new([string[]]@($staticEntry.Options | ForEach-Object { $_.Token }), [System.StringComparer]::Ordinal)

    $merged = [pscustomobject]@{
        Subcommands = @(
            $staticEntry.Subcommands
            $live.Subcommands | Where-Object { $subcommandNames.Add($_.Name) }
        )
        Options     = @(
            $staticEntry.Options
            $live.Options | Where-Object { $optionTokens.Add($_.Token) }
        )
    }

    $cache.Entries[$Key] = $merged
    $merged
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

    # The last element is the word being completed when it holds the cursor. An
    # unquoted a,b list is one array-literal element while $WordToComplete is
    # only its last segment, so text equality alone would miss it.
    $lastExtent = $CommandAst.CommandElements[-1].Extent
    $cursorInLast = $lastExtent.StartOffset -lt $CursorPosition -and $lastExtent.EndOffset -ge $CursorPosition
    if ($arguments.Count -gt 0 -and ($arguments[-1] -eq $WordToComplete -or $cursorInLast)) {
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
            # Only a word the static table does not know reads the live help
            # page, and only the current command's page, which the returned
            # Entry needs anyway. Click takes a group's first plain word as its
            # subcommand, so an unknown word that is not the value of the
            # option before it ends the path and no deeper page is read.
            $liveEntry = Get-ApmCatalogEntry -Key $currentKey
            $match = $liveEntry.Subcommands | Where-Object { $_.Name -eq $arg } | Select-Object -First 1
            if ($null -eq $match) {
                $prior = if ($i -gt 0) { $ArgsBeforeCursor[$i - 1] } else { '' }
                $priorOption = $liveEntry.Options | Where-Object { $_.Token -eq $prior } | Select-Object -First 1
                if ($null -ne $priorOption -and $priorOption.ValueKind -ne 'flag') {
                    continue
                }

                break
            }
        }

        $commandPath.Add($match.Name)
        $currentKey = if ([string]::IsNullOrEmpty($currentKey)) {
            $match.Name
        }
        else {
            "$currentKey $($match.Name)"
        }

        $currentEntry = if ($catalog.Contains($currentKey)) {
            $catalog[$currentKey]
        }
        else {
            [pscustomobject]@{ Subcommands = @(); Options = @() }
        }
        $lastPathIndex = $i
    }

    [pscustomobject]@{
        Key           = $currentKey
        Entry         = Get-ApmCatalogEntry -Key $currentKey
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
            # Click gives an optional value ('--registry [NAME]') the next word
            # unless that word is an option.
            $leavesValueOut = $optionLookup[$pendingOption].OptionalValue -and $arg -match '^-.'
            $pendingOption = $null
            if (-not $leavesValueOut) {
                continue
            }
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
        [string]$AttachedPrefix = '',
        [string]$ElementText = ''
    )

    switch ($Option.ValueKind) {
        'enum' {
            return @(Get-ApmClosedValueCompletions -Values $Option.Values -WordToComplete $WordToComplete -AttachedPrefix $AttachedPrefix)
        }
        'list' {
            return @(Get-ApmListValueCompletion -Values $Option.Values -WordToComplete $WordToComplete -AttachedPrefix $AttachedPrefix -ElementText $ElementText)
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

    $configKeys = (Get-Variable -Name ApmConfigKeyValues -Scope Script -ErrorAction Ignore).Value
    $booleanValues = (Get-Variable -Name ApmBooleanValues -Scope Script -ErrorAction Ignore).Value
    $runtimeValues = (Get-Variable -Name ApmRuntimeValues -Scope Script -ErrorAction Ignore).Value
    $lifecycleEvents = (Get-Variable -Name ApmLifecycleEventValues -Scope Script -ErrorAction Ignore).Value

    switch ($CommandKey) {
        'auth' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('github.com', 'gitlab.com') -WordToComplete $WordToComplete)
            }
        }
        'update' {
            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
        }
        'approve' {
            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
        }
        'deny' {
            return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
        }
        'find' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<file-path>')
            }
        }
        'deps why' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
            }
        }
        'policy explain' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package>') -WordToComplete $WordToComplete)
            }
        }
        'experimental enable' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<feature>') -WordToComplete $WordToComplete)
            }
        }
        'experimental disable' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<feature>') -WordToComplete $WordToComplete)
            }
        }
        'experimental reset' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<feature>') -WordToComplete $WordToComplete)
            }
        }
        'lifecycle test' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmClosedValueCompletions -Values $lifecycleEvents -WordToComplete $WordToComplete)
            }
        }
        'plugin init' {
            if ($Analysis.Positionals.Count -eq 0) {
                if (Test-ApmPathLikeToken -Token $WordToComplete) {
                    return @(Get-ApmPathCompletions -PathPrefix $WordToComplete -Placeholder '<project-name>')
                }

                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('.', '<project-name>') -WordToComplete $WordToComplete)
            }
        }
        'mcp install' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<server-name>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace validate' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<marketplace>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace audit' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<marketplace>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace package add' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<owner/repo>', '<host/owner/repo>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace package remove' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package-name>') -WordToComplete $WordToComplete)
            }
        }
        'marketplace package set' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmFreeformValueCompletions -SuggestedValues @('<package-name>') -WordToComplete $WordToComplete)
            }
        }
        'config unset' {
            if ($Analysis.Positionals.Count -eq 0) {
                return @(Get-ApmClosedValueCompletions -Values $configKeys -WordToComplete $WordToComplete)
            }
        }
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
    # [object[]] so a single CompletionResult (PowerShell unrolls one-element
    # arrays on function return) binds as a one-element array instead of failing
    # IEnumerable parameter transformation.
    param([object[]]$Results)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($result in @($Results)) {
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

    # The parser's element under the cursor, up to the cursor: for an unquoted
    # comma list it holds the earlier segments $WordToComplete lacks.
    $elementText = ''
    $cursorElement = $CommandAst.CommandElements | Select-Object -Skip 1 | Where-Object {
        $_.Extent.StartOffset -lt $CursorPosition -and $_.Extent.EndOffset -ge $CursorPosition
    } | Select-Object -First 1
    if ($null -ne $cursorElement) {
        $elementText = $cursorElement.Extent.Text.Substring(0, $CursorPosition - $cursorElement.Extent.StartOffset)
    }

    if ($WordToComplete -match '^(?<option>-{1,2}[^=]+)=(?<value>.*)$') {
        $optionName = $Matches.option
        if ($optionLookup.ContainsKey($optionName)) {
            $attachedPrefix = "$optionName="
            return Get-ApmUniqueResults -Results @(Get-ApmOptionValueResults -CommandKey $context.Key -Option $optionLookup[$optionName] -WordToComplete $WordToComplete -AttachedPrefix $attachedPrefix -ElementText $elementText)
        }
    }
    elseif ($elementText -match '^(?<option>-{1,2}[^=]+)=.*,') {
        $optionName = $Matches.option
        if ($optionLookup.ContainsKey($optionName) -and $optionLookup[$optionName].ValueKind -eq 'list') {
            return Get-ApmUniqueResults -Results @(Get-ApmOptionValueResults -CommandKey $context.Key -Option $optionLookup[$optionName] -WordToComplete $WordToComplete -AttachedPrefix "$optionName=" -ElementText $elementText)
        }
    }

    $results = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    if ($null -ne $analysis.PendingOption -and $optionLookup.ContainsKey($analysis.PendingOption)) {
        $pendingOption = $optionLookup[$analysis.PendingOption]
        $valueResults = @(Get-ApmOptionValueResults -CommandKey $context.Key -Option $pendingOption -WordToComplete $WordToComplete -ElementText $elementText)
        if (-not $pendingOption.OptionalValue) {
            return Get-ApmUniqueResults -Results $valueResults
        }

        # A bare optional-value option is complete when an option follows it,
        # so the slot offers the value placeholder and the command's options.
        # A plain word would become the value, so positionals stay out.
        if (-not $WordToComplete.StartsWith('-')) {
            foreach ($valueResult in $valueResults) {
                $results.Add($valueResult)
            }
        }

        if ([string]::IsNullOrEmpty($WordToComplete) -or $WordToComplete.StartsWith('-')) {
            foreach ($option in $context.Entry.Options) {
                if (Test-ApmStartsWith -Candidate $option.Token -Prefix $WordToComplete) {
                    $results.Add((New-ApmCompletionResult -CompletionText $option.Token -ToolTip $option.Description -ResultType ([System.Management.Automation.CompletionResultType]::ParameterName)))
                }
            }
        }

        return Get-ApmUniqueResults $results
    }

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

<#
.SYNOPSIS
    Argument completer for winapp / winapp.exe (Windows app development CLI).
.DESCRIPTION
    Schema-driven tab completion for winapp.  On the first completion request the
    completer lazily invokes `winapp --cli-schema`, parses the JSON command tree,
    and caches it for the rest of the session.  Completion then walks the live
    tree generically to offer subcommands, options (short and long aliases),
    option values, and positional value slots.

    A small static overlay supplies enum choices that the schema does not carry
    (IfExists, SdkInstallMode, ManifestTemplates).  File / directory slots use
    the built-in filename completer; free-form slots emit a typed placeholder.

    The completer never invokes winapp more than once (probe-once) and never
    throws: if winapp is missing or the schema cannot be parsed, completion is a
    graceful no-op.  Dot-source this file from your $PROFILE to enable completion
    for both invocation forms.

    Safe to source multiple times (idempotent registration via script-scoped guard).
.EXAMPLE
    . "$PSScriptRoot\winapp_completer.ps1"
#>

Set-StrictMode -Version Latest

#region -- Lazy data initialisation -------------------------------------------------------------

# Lazily fetch + parse `winapp --cli-schema` exactly once and build the static
# enum overlay.  This is the ONLY function that runs external commands or mutates
# script-scoped state.  It never throws and is safe to call on every completion.
function Initialize-WinAppCompleterData {
    if (Get-Variable -Name WinAppSchemaProbed -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    # Probe-once: set this first so a failed probe is never retried.
    $script:WinAppSchemaProbed = $true
    $script:WinAppTree         = $null

    # Static enum overlay.  Schema enum options carry no choices, so map by a
    # substring of the valueType (handles the System.Nullable<...> wrapper).
    $script:WinAppEnumChoices = @{
        'IfExists'          = @('Error', 'Overwrite', 'Skip')
        'SdkInstallMode'    = @('stable', 'preview', 'experimental', 'none')
        'ManifestTemplates' = @('Packaged', 'Sparse')
    }

    try {
        $command = Get-Command -Name winapp -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $command) { return }

        $exePath = if ($command.Source) { $command.Source } else { $command.Path }
        if ([string]::IsNullOrWhiteSpace($exePath)) { return }

        $schemaJson = & $exePath --cli-schema 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($schemaJson)) { return }

        $script:WinAppTree = $schemaJson | ConvertFrom-Json
    } catch {
        $script:WinAppTree = $null
    }
}

#endregion

#region -- Helpers ------------------------------------------------------------------------------

function New-WinAppCompletion {
    param(
        [Parameter(Mandatory)]
        [string]$CompletionText,

        [string]$ListItemText = '',
        [string]$Tooltip      = '',

        [System.Management.Automation.CompletionResultType]
        $ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue
    )
    if ([string]::IsNullOrEmpty($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrEmpty($Tooltip))      { $Tooltip      = $ListItemText  }
    [System.Management.Automation.CompletionResult]::new(
        $CompletionText, $ListItemText, $ResultType, $Tooltip
    )
}

# Returns $true when a PSCustomObject node carries the named property.  Guards
# every schema access so containers/leaves/passthrough nodes never trip StrictMode.
function Test-WinAppNodeProperty {
    param($Node, [string]$Name)
    if ($null -eq $Node) { return $false }
    return ($Node.PSObject.Properties.Name -contains $Name)
}

# Walks the live tree from the root to the node addressed by the resolved command
# tokens.  Returns the deepest resolved node, or $null when the tree is absent.
function Get-WinAppNode {
    param([string]$Cmd1, [string]$Cmd2)

    if ($null -eq $script:WinAppTree) { return $null }
    $node = $script:WinAppTree

    if ($Cmd1) {
        if (-not (Test-WinAppNodeProperty $node 'subcommands')) { return $node }
        if (-not (Test-WinAppNodeProperty $node.subcommands $Cmd1)) { return $node }
        $node = $node.subcommands.$Cmd1
    }
    if ($Cmd2) {
        if (-not (Test-WinAppNodeProperty $node 'subcommands')) { return $node }
        if (-not (Test-WinAppNodeProperty $node.subcommands $Cmd2)) { return $node }
        $node = $node.subcommands.$Cmd2
    }
    return $node
}

# Returns the option node object for a (possibly aliased) token in the given
# command node, or $null.  Alias-aware and generic (reads each option's aliases).
function Get-WinAppOption {
    param($Node, [string]$Token)

    if (-not (Test-WinAppNodeProperty $Node 'options')) { return $null }
    $options = $Node.options

    # Direct canonical match.
    if (Test-WinAppNodeProperty $options $Token) {
        return $options.$Token
    }

    # Alias match: scan each option's aliases array.
    foreach ($optProp in $options.PSObject.Properties) {
        $opt = $optProp.Value
        if (Test-WinAppNodeProperty $opt 'aliases') {
            foreach ($alias in $opt.aliases) {
                if ($alias -eq $Token) { return $opt }
            }
        }
    }
    return $null
}

# Resolves a (possibly aliased) option token to its canonical option name in the
# given node, or returns the token unchanged when no match exists.
function Resolve-WinAppOptionName {
    param($Node, [string]$Token)

    if (-not (Test-WinAppNodeProperty $Node 'options')) { return $Token }
    $options = $Node.options

    if (Test-WinAppNodeProperty $options $Token) { return $Token }

    foreach ($optProp in $options.PSObject.Properties) {
        $opt = $optProp.Value
        if (Test-WinAppNodeProperty $opt 'aliases') {
            foreach ($alias in $opt.aliases) {
                if ($alias -eq $Token) { return $optProp.Name }
            }
        }
    }
    return $Token
}

# Returns $true unless the option is a pure switch (Boolean / Void never consume
# the next token).  Resolves the global recursive options against the root too.
function Test-WinAppOptionTakesValue {
    param($Node, [string]$Token)

    $opt = Get-WinAppOption -Node $Node -Token $Token
    if ($null -eq $opt) {
        # Fall back to the recursive global options on the root.
        $opt = Get-WinAppOption -Node $script:WinAppTree -Token $Token
    }
    if ($null -eq $opt) { return $false }
    if (-not (Test-WinAppNodeProperty $opt 'valueType')) { return $false }

    $vt = $opt.valueType
    if ($vt -eq 'System.Boolean' -or $vt -eq 'System.Void') { return $false }
    return $true
}

# Returns the overlay enum choices when the valueType string contains a known
# enum key (handles the System.Nullable<...> wrapper), else $null.
function Get-WinAppEnumChoices {
    param([string]$ValueType)
    if ([string]::IsNullOrEmpty($ValueType)) { return $null }
    foreach ($key in $script:WinAppEnumChoices.Keys) {
        if ($ValueType -like "*$key*") {
            return $script:WinAppEnumChoices[$key]
        }
    }
    return $null
}

# Emits value completions for a value-taking option based on its valueType.
# Supports inline (--flag=) completion through $InlinePrefix.
function Write-WinAppOptionValue {
    param(
        $Node,
        [string]$OptionToken,
        [string]$WordToComplete,
        [string]$InlinePrefix = ''
    )

    $opt = Get-WinAppOption -Node $Node -Token $OptionToken
    if ($null -eq $opt) {
        $opt = Get-WinAppOption -Node $script:WinAppTree -Token $OptionToken
    }
    if ($null -eq $opt) { return }

    $valueType = if (Test-WinAppNodeProperty $opt 'valueType') { $opt.valueType } else { '' }
    $helpName  = if (Test-WinAppNodeProperty $opt 'helpName')  { $opt.helpName }  else { '' }
    $canonical = Resolve-WinAppOptionName -Node $Node -Token $OptionToken

    # 0. Switches (Boolean / Void) never take a value: emit nothing so an inline
    #    --switch= (e.g. --verbose=) does not produce a spurious <value> placeholder.
    if ($valueType -eq 'System.Boolean' -or $valueType -eq 'System.Void') { return }

    # 1. Enum overlay.
    $enumVals = Get-WinAppEnumChoices -ValueType $valueType
    if ($enumVals) {
        $enumVals | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
            $tip = "$canonical value: $_"
            if ($InlinePrefix) {
                New-WinAppCompletion "$InlinePrefix$_" -ListItemText $_ -Tooltip $tip
            } else {
                New-WinAppCompletion $_ -Tooltip $tip
            }
        }
        return
    }

    # 2. File path (files + directories).
    if ($valueType -like '*System.IO.FileInfo*') {
        [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete) |
            ForEach-Object {
                if ($InlinePrefix) {
                    New-WinAppCompletion "$InlinePrefix$($_.CompletionText)" `
                        -ListItemText $_.ListItemText `
                        -ResultType   $_.ResultType `
                        -Tooltip      $_.ToolTip
                } else {
                    $_
                }
            }
        return
    }

    # 3. Directory path (directories only).
    if ($valueType -like '*System.IO.DirectoryInfo*') {
        Write-WinAppDirectoryCompletion -WordToComplete $WordToComplete -InlinePrefix $InlinePrefix
        return
    }

    # 4. Numeric placeholder.
    if ($valueType -like '*System.Int32*' -or $valueType -like '*System.Int64*') {
        if ('' -like "$WordToComplete*") {
            $text = if ($InlinePrefix) { "$InlinePrefix<n>" } else { '<n>' }
            New-WinAppCompletion $text -ListItemText '<n>' -Tooltip "Numeric value for $canonical"
        }
        return
    }

    # 5. Generic string placeholder (suppresses filesystem fallback).
    if ('' -like "$WordToComplete*") {
        $ph = if ($helpName) { "<$helpName>" } else { '<value>' }
        $text = if ($InlinePrefix) { "$InlinePrefix$ph" } else { $ph }
        New-WinAppCompletion $text -ListItemText $ph -Tooltip "Value for $canonical"
    }
}

# Directory-only completion (filters CompleteFilename results to containers).
function Write-WinAppDirectoryCompletion {
    param(
        [string]$WordToComplete,
        [string]$InlinePrefix = ''
    )
    [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete) |
        Where-Object {
            $_.ResultType -eq [System.Management.Automation.CompletionResultType]::ProviderContainer
        } |
        ForEach-Object {
            if ($InlinePrefix) {
                New-WinAppCompletion "$InlinePrefix$($_.CompletionText)" `
                    -ListItemText $_.ListItemText `
                    -ResultType   $_.ResultType `
                    -Tooltip      $_.ToolTip
            } else {
                $_
            }
        }
}

# Builds the canonical option name -> option-node map for the current node,
# unioned with the recursive global options on the root.  Node options win on
# name collisions.
function Get-WinAppOptionMap {
    param($Node)

    $map = [ordered]@{}

    # Recursive global options from the root first.
    if (Test-WinAppNodeProperty $script:WinAppTree 'options') {
        foreach ($p in $script:WinAppTree.options.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
    }
    # Node-local options override.
    if (Test-WinAppNodeProperty $Node 'options') {
        foreach ($p in $Node.options.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
    }
    return $map
}

# Emits ParameterName results for the current node's options (unioned with global
# recursive options), filtered by the typed prefix.  Single-dash prefixes offer
# matching short/long aliases; otherwise canonical long names are offered.
function Write-WinAppOptionList {
    param(
        $Node,
        [string]$WordToComplete
    )

    $map     = Get-WinAppOptionMap -Node $Node
    $isShort = ($WordToComplete -like '-*') -and ($WordToComplete -notlike '--*')

    foreach ($entry in $map.GetEnumerator()) {
        $name = $entry.Key
        $opt  = $entry.Value

        $desc = if (Test-WinAppNodeProperty $opt 'description') { $opt.description } else { '' }
        $type = if (Test-WinAppNodeProperty $opt 'valueType')   { $opt.valueType }   else { '' }
        $typeTag = Get-WinAppTypeTag -ValueType $type

        $aliases = @()
        if (Test-WinAppNodeProperty $opt 'aliases') { $aliases = @($opt.aliases) }

        if ($isShort) {
            # Offer any alias (short or long) that matches what was typed.
            foreach ($alias in $aliases) {
                if ($alias -notlike "$WordToComplete*") { continue }
                $tip = "$alias -> ${name} ${typeTag}: $desc"
                New-WinAppCompletion $alias -ResultType ParameterName -Tooltip $tip
            }
        } else {
            $aliasNote = if ($aliases.Count -gt 0) { " (alias: $($aliases -join ', '))" } else { '' }
            if ($name -like "$WordToComplete*") {
                $tip = "${name}${aliasNote} ${typeTag}: $desc"
                New-WinAppCompletion $name -ResultType ParameterName -Tooltip $tip
            }
            # Surface long-form aliases (e.g. --no-config -> --ignore-config) that
            # match the typed prefix even when the canonical name does not.
            foreach ($alias in $aliases) {
                if ($alias -notlike '--*') { continue }
                if ($alias -notlike "$WordToComplete*") { continue }
                $tip = "$alias -> ${name} ${typeTag}: $desc"
                New-WinAppCompletion $alias -ResultType ParameterName -Tooltip $tip
            }
        }
    }
}

# Maps a valueType string to a short human-readable tag for tooltips.
function Get-WinAppTypeTag {
    param([string]$ValueType)
    if ([string]::IsNullOrEmpty($ValueType))            { return '[flag]' }
    if ($ValueType -eq 'System.Boolean')                { return '[switch]' }
    if ($ValueType -eq 'System.Void')                   { return '[switch]' }
    if (Get-WinAppEnumChoices -ValueType $ValueType)    { return '[enum]' }
    if ($ValueType -like '*System.IO.FileInfo*')        { return '[file]' }
    if ($ValueType -like '*System.IO.DirectoryInfo*')   { return '[dir]' }
    if ($ValueType -like '*System.Int32*')              { return '[number]' }
    if ($ValueType -like '*System.Int64*')              { return '[number]' }
    if ($ValueType -like '*`[`]*')                      { return '[array]' }
    return '[string]'
}

# Returns the ordered list of positional argument nodes for a leaf node, sorted
# by their declared order, or an empty array.
function Get-WinAppPositionalArgs {
    param($Node)
    if (-not (Test-WinAppNodeProperty $Node 'arguments')) { return @() }
    $argList = foreach ($p in $Node.arguments.PSObject.Properties) {
        $order = if (Test-WinAppNodeProperty $p.Value 'order') { [int]$p.Value.order } else { 0 }
        [pscustomobject]@{ Name = $p.Name; Node = $p.Value; Order = $order }
    }
    return @($argList | Sort-Object Order)
}

# Returns the argument node for the positional slot currently being completed,
# given how many positionals are already committed.  Trailing array args
# (String[]/[]) repeat for slots beyond the declared count.
function Get-WinAppPositionalSlot {
    param($Node, [int]$ConsumedCount)

    $argSlots = Get-WinAppPositionalArgs -Node $Node
    if ($argSlots.Count -eq 0) { return $null }

    if ($ConsumedCount -lt $argSlots.Count) {
        return $argSlots[$ConsumedCount]
    }

    # Beyond the declared slots: reuse the last arg if it is a repeating array.
    $last = $argSlots[-1]
    $vt = if (Test-WinAppNodeProperty $last.Node 'valueType') { $last.Node.valueType } else { '' }
    if ($vt -like '*`[`]*') { return $last }
    return $null
}

# Emits completion for a positional argument slot based on its valueType.
function Write-WinAppPositionalValue {
    param($Slot, [string]$WordToComplete)

    if ($null -eq $Slot) { return }
    $argNode  = $Slot.Node
    $valueType = if (Test-WinAppNodeProperty $argNode 'valueType') { $argNode.valueType } else { '' }
    $name      = $Slot.Name

    if ($valueType -like '*System.IO.FileInfo*') {
        [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
        return
    }
    if ($valueType -like '*System.IO.DirectoryInfo*') {
        Write-WinAppDirectoryCompletion -WordToComplete $WordToComplete
        return
    }

    # Free-form string / string[] -> name-based placeholder.
    if ('' -like "$WordToComplete*") {
        New-WinAppCompletion "<$name>" -Tooltip "Positional value: $name"
    }
}

# Emits subcommand-name completions for a container node, filtered by prefix.
function Write-WinAppSubcommandList {
    param($Node, [string]$WordToComplete)

    if (-not (Test-WinAppNodeProperty $Node 'subcommands')) { return }
    foreach ($p in $Node.subcommands.PSObject.Properties) {
        if ($p.Name -notlike "$WordToComplete*") { continue }
        $desc = if (Test-WinAppNodeProperty $p.Value 'description') { $p.Value.description } else { $p.Name }
        New-WinAppCompletion $p.Name -Tooltip $desc
    }
}

# A container is a node that has subcommands and no own options/arguments.
function Test-WinAppIsContainer {
    param($Node)
    if (-not (Test-WinAppNodeProperty $Node 'subcommands')) { return $false }
    if (Test-WinAppNodeProperty $Node 'options')   { return $false }
    if (Test-WinAppNodeProperty $Node 'arguments') { return $false }
    return $true
}

#endregion

#region -- Completer scriptblock ----------------------------------------------------------------

function Complete-WinAppNative {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameter
    )

    Initialize-WinAppCompleterData

    # No usable schema -> graceful no-op.
    if ($null -eq $script:WinAppTree) { return }

    # -------------------------------------------------------------------------
    # Detect the native ReadLine calling convention vs TabExpansion2.
    #
    # Native convention (ReadLine):
    #   A) after trailing space: $CommandName='', $ParameterName='<full line>',
    #      $WordToComplete='<cursor col>'
    #   B) mid-token: $CommandName='<partial>', $ParameterName='<full line>',
    #      $WordToComplete='<cursor col>'
    #
    # TabExpansion2 native path:
    #   $CommandName='<wordToComplete>', $ParameterName=<CommandAst object>,
    #   $WordToComplete='<cursorPosition int>'
    #
    # Heuristic: $WordToComplete is a pure integer AND $ParameterName coerces
    # to something that looks like a command line (starts with a non-space word).
    # -------------------------------------------------------------------------
    $isNativeConvention = $WordToComplete -match '^\d+$' -and
                          $ParameterName  -match '^\s*\S+'

    if ($isNativeConvention) {
        $nativePartialWord = $CommandName
        $cursorCol         = [int]$WordToComplete

        if ($ParameterName -is [System.Management.Automation.Language.CommandAst]) {
            $CommandAst = $ParameterName
            $line       = $CommandAst.Extent.Text
        } else {
            $line      = [string]$ParameterName
            $tokens    = $null
            $parseErrs = $null
            $parsedAst = [System.Management.Automation.Language.Parser]::ParseInput(
                             $line, [ref]$tokens, [ref]$parseErrs)
            if ($parsedAst.EndBlock.Statements.Count -gt 0) {
                $pipeline = $parsedAst.EndBlock.Statements[0]
                if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and
                    $pipeline.PipelineElements.Count -gt 0 -and
                    $pipeline.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst]) {
                    $CommandAst = $pipeline.PipelineElements[0]
                }
            }
        }

        if ($null -ne $CommandAst -and $CommandAst.CommandElements.Count -gt 1) {
            $lastEl     = $CommandAst.CommandElements[-1]
            $lastEnd    = $lastEl.Extent.EndOffset
            $lastTokVal = $lastEl.Extent.Text
            $cursorPastEnd = $cursorCol -ge $line.Length
            $cursorPastTok = $cursorCol -gt $lastEnd -and
                             ($cursorCol -gt $line.Length -or
                              [char]::IsWhiteSpace($line[$cursorCol - 1]))

            # A token is "complete" when it is a known live top-level subcommand
            # or a finished flag (-* with no trailing '=').
            $topNames = @()
            if (Test-WinAppNodeProperty $script:WinAppTree 'subcommands') {
                $topNames = $script:WinAppTree.subcommands.PSObject.Properties.Name
            }
            $isCompleteTok = ($topNames -contains $lastTokVal) -or
                             (($lastTokVal -like '-*') -and
                              $lastTokVal -notlike '*=*' -and
                              $lastTokVal.Length -gt 1 -and
                              $lastTokVal -ne '-')
            $hasTrailingSpace = $cursorPastTok -or
                                ($cursorPastEnd -and $isCompleteTok -and $cursorCol -gt $lastEnd)

            if ($hasTrailingSpace) {
                $WordToComplete = ''
            } elseif (-not [string]::IsNullOrEmpty($nativePartialWord)) {
                $WordToComplete = $nativePartialWord
            } else {
                $pfx = if ($cursorCol -le $line.Length) {
                           $line.Substring(0, $cursorCol)
                       } else { $line }
                $trimmed = $pfx.TrimEnd()
                $spc     = $trimmed.LastIndexOf(' ')
                if ($spc -ge 0) {
                    $WordToComplete = $trimmed.Substring($spc + 1)
                } else {
                    $fspc = $trimmed.IndexOf(' ')
                    $WordToComplete = if ($fspc -ge 0) {
                                         $trimmed.Substring($fspc + 1)
                                     } else { '' }
                }
            }
        } else {
            $WordToComplete = ''
        }
    }

    if ($null -eq $WordToComplete) { $WordToComplete = '' }
    if ($null -eq $CommandAst)     { return }

    $allElements = @($CommandAst.CommandElements)
    if ($allElements.Count -eq 0) { return }

    # -------------------------------------------------------------------------
    # Build the committed argument list using Extent.Text for every node so the
    # walk is safe under StrictMode (CommandParameterAst lacks a .Value property).
    # -------------------------------------------------------------------------
    $allArgs = @(foreach ($el in ($allElements | Select-Object -Skip 1)) {
        $el.Extent.Text
    })

    # Exclude the word being completed from the committed positionals, but keep
    # it for flags so Test-WinAppOptionTakesValue can set expectingValue.
    if ($allArgs.Count -gt 0 -and $allArgs[-1] -eq $WordToComplete) {
        if ($WordToComplete -like '-*') {
            $committedArgs = $allArgs
        } else {
            $cnt = $allArgs.Count - 2
            $committedArgs = if ($cnt -lt 0) { @() } else { $allArgs[0..$cnt] }
        }
    } else {
        $committedArgs = $allArgs
    }

    # -------------------------------------------------------------------------
    # State machine: walk committed args to determine the current node context.
    # -------------------------------------------------------------------------
    $cmd1            = $null   # top-level subcommand
    $cmd2            = $null   # sub-sub command (under a container)
    $expectingValue  = $false
    $currentOption   = $null
    $positionalCount = 0

    foreach ($token in $committedArgs) {
        if ($expectingValue) {
            $expectingValue = $false
            $currentOption  = $null
            continue
        }

        if ($token -like '-*') {
            if ($token -like '*=*') { continue }   # inline --flag=value
            $node = Get-WinAppNode -Cmd1 $cmd1 -Cmd2 $cmd2
            if (Test-WinAppOptionTakesValue -Node $node -Token $token) {
                $expectingValue = $true
                $currentOption  = $token
            }
            continue
        }

        # Positional token: descend the tree where possible.
        if ($null -eq $cmd1) {
            if ((Test-WinAppNodeProperty $script:WinAppTree 'subcommands') -and
                (Test-WinAppNodeProperty $script:WinAppTree.subcommands $token)) {
                $cmd1 = $token
                continue
            }
            $positionalCount++
            continue
        }

        if ($null -eq $cmd2) {
            $c1node = Get-WinAppNode -Cmd1 $cmd1
            if ((Test-WinAppIsContainer $c1node) -and
                (Test-WinAppNodeProperty $c1node.subcommands $token)) {
                $cmd2 = $token
                continue
            }
            $positionalCount++
            continue
        }

        $positionalCount++
    }

    $currentNode = Get-WinAppNode -Cmd1 $cmd1 -Cmd2 $cmd2
    if ($null -eq $currentNode) { $currentNode = $script:WinAppTree }

    # =========================================================================
    # 1.  Inline --flag=value completion
    # =========================================================================
    if ($WordToComplete -like '-*' -and $WordToComplete -like '*=*') {
        $eqIdx    = $WordToComplete.IndexOf('=')
        $flagPart = $WordToComplete.Substring(0, $eqIdx)
        $valPfx   = $WordToComplete.Substring($eqIdx + 1)
        Write-WinAppOptionValue -Node $currentNode -OptionToken $flagPart `
            -WordToComplete $valPfx -InlinePrefix "$flagPart="
        return
    }

    # =========================================================================
    # 2.  Value completion after a space-separated value-taking option
    # =========================================================================
    if ($expectingValue) {
        Write-WinAppOptionValue -Node $currentNode -OptionToken $currentOption `
            -WordToComplete $WordToComplete
        return
    }

    # =========================================================================
    # 3.  Option completion (word starts with - or --)
    # =========================================================================
    if ($WordToComplete -like '-*') {
        Write-WinAppOptionList -Node $currentNode -WordToComplete $WordToComplete
        return
    }

    # =========================================================================
    # 4.  Subcommand / positional completion
    # =========================================================================

    # 4a. Container node (cert / manifest / ui) awaiting its subcommand.
    if ((Test-WinAppIsContainer $currentNode) -and $null -eq $cmd2) {
        Write-WinAppSubcommandList -Node $currentNode -WordToComplete $WordToComplete
        return
    }

    # 4b. Leaf node -> positional slot completion (+ option list when empty word).
    if (Test-WinAppNodeProperty $currentNode 'arguments') {
        $slot = Get-WinAppPositionalSlot -Node $currentNode -ConsumedCount $positionalCount
        Write-WinAppPositionalValue -Slot $slot -WordToComplete $WordToComplete

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-WinAppOptionList -Node $currentNode -WordToComplete ''
        }
        return
    }

    # 4c. Leaf node with no positionals but its own options -> offer options on
    #     an empty word so `winapp <leaf> <Tab>` is useful.
    if ($cmd1 -and (Test-WinAppNodeProperty $currentNode 'options')) {
        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-WinAppOptionList -Node $currentNode -WordToComplete ''
        }
        return
    }

    # 4d. A command is resolved but it is a passthrough leaf (no subcommands,
    #     arguments, or options, e.g. 'store') -> nothing to offer.
    if ($cmd1) { return }

    # 4e. Root (nothing resolved) -> top-level subcommands.
    Write-WinAppSubcommandList -Node $script:WinAppTree -WordToComplete $WordToComplete
}

#endregion

#region -- Registration -------------------------------------------------------------------------

if (-not ((Get-Variable -Name WinAppCompleterRegistered -Scope Script -ErrorAction SilentlyContinue) -and $script:WinAppCompleterRegistered)) {
    Register-ArgumentCompleter -CommandName @('winapp', 'winapp.exe') -Native -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
        Complete-WinAppNative -CommandName $commandName -ParameterName $parameterName -WordToComplete $wordToComplete -CommandAst $commandAst -FakeBoundParameter $fakeBoundParameter
    }
    $script:WinAppCompleterRegistered = $true
}

#endregion

# curl tab completion for PowerShell
# Builds a help-driven option catalog for curl.exe and adds value-aware completion.

Set-StrictMode -Version 2.0

function New-CurlCompletionResult {
    param(
        [string]$CompletionText,
        [string]$ResultType,
        [string]$ToolTip,
        [string]$ListItemText
    )

    if ([string]::IsNullOrWhiteSpace($ListItemText)) {
        $ListItemText = $CompletionText
    }

    if ([string]::IsNullOrWhiteSpace($ToolTip)) {
        $ToolTip = $CompletionText
    }

    [System.Management.Automation.CompletionResult]::new(
        $CompletionText,
        $ListItemText,
        $ResultType,
        $ToolTip
    )
}

function Get-CurlUniqueStrings {
    param([string[]]$Items)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results = New-Object System.Collections.Generic.List[string]

    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        if ($seen.Add($item)) {
            [void]$results.Add($item)
        }
    }

    @($results.ToArray())
}

function Get-CurlDefaultHelpSubjects {
    @(
        'all',
        'auth',
        'category',
        'connection',
        'curl',
        'deprecated',
        'dns',
        'file',
        'ftp',
        'global',
        'http',
        'imap',
        'ldap',
        'output',
        'pop3',
        'post',
        'proxy',
        'scp',
        'sftp',
        'smtp',
        'ssh',
        'telnet',
        'tftp',
        'timeout',
        'tls',
        'upload',
        'verbose',
        'manual'
    )
}

function Get-CurlCompletionCatalog {
    if (Get-Variable -Name CurlCompletionCatalog -Scope Script -ErrorAction SilentlyContinue) {
        return $script:CurlCompletionCatalog
    }

    $script:CurlCompletionCatalog = @{
        Initialized   = $false
        CommandName   = $null
        HelpSubjects  = Get-CurlDefaultHelpSubjects
        Protocols     = @()
        Options       = @()
        OptionByToken = @{}
    }

    $script:CurlCompletionCatalog
}

function Resolve-CurlCommandName {
    $catalog = Get-CurlCompletionCatalog
    if ($catalog.CommandName) {
        return $catalog.CommandName
    }

    $command = Get-Command -Name curl.exe, curl -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        $catalog.CommandName = if ($command.Source) { $command.Source } else { $command.Name }
    }

    $catalog.CommandName
}

function Invoke-CurlCapture {
    param([string[]]$Arguments)

    $commandName = Resolve-CurlCommandName
    if (-not $commandName) {
        return @()
    }

    try {
        @(& $commandName @Arguments 2>$null)
    } catch {
        @()
    }
}

function Remove-CurlOuterQuotes {
    param([string]$Value)

    if ($null -eq $Value) {
        return ''
    }

    $Value.Trim([char[]]@([char]34, [char]39))
}

function ConvertTo-CurlQuotedValue {
    param(
        [string]$Value,
        [bool]$AlwaysQuote = $false
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    if (($AlwaysQuote -or $Value -match '\s') -and -not ($Value.StartsWith('"') -and $Value.EndsWith('"'))) {
        $escaped = $Value.Replace('`', '``').Replace('"', '`"')
        return '"' + $escaped + '"'
    }

    $Value
}

function Test-CurlPathLikeInput {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $cleanValue = Remove-CurlOuterQuotes -Value $Value
    $cleanValue -match '^(?:\.{1,2}[\\/]|[\\/]|~[\\/]|[A-Za-z]:|\\\\)'
}

function Get-CurlTokenText {
    param([System.Management.Automation.Language.Ast]$Element)

    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Element.Value
    }

    if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
        return $Element.Extent.Text
    }

    $Element.Extent.Text
}

function Get-CurlCurrentToken {
    param(
        [string]$Line,
        [int]$CursorPosition,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $Fallback
    }

    $safeCursor = [Math]::Min([Math]::Max($CursorPosition, 0), $Line.Length)
    $prefix = $Line.Substring(0, $safeCursor)
    if ($prefix -match '\s$') {
        return ''
    }

    $parts = @([regex]::Matches($prefix, '"[^"]*"|''[^'']*''|\S+') | ForEach-Object { $_.Value })
    if ($parts.Count -gt 0) {
        return $parts[-1]
    }

    $Fallback
}

function Get-CurlArgumentTokens {
    param(
        [System.Management.Automation.Language.CommandAst]$CommandAst,
        [int]$CursorPosition
    )

    $tokens = @()
    foreach ($element in $CommandAst.CommandElements | Select-Object -Skip 1) {
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            $tokens += Get-CurlTokenText -Element $element
        }
    }

    $tokens
}

function Get-CurlValueKind {
    param(
        [string]$Token,
        [string]$Placeholder
    )

    $tokenKey = $Token.ToLowerInvariant()
    $placeholderKey = if ([string]::IsNullOrWhiteSpace($Placeholder)) { '' } else { $Placeholder.ToLowerInvariant() }

    switch ($tokenKey) {
        '-h' { return 'HelpSubject' }
        '--help' { return 'HelpSubject' }
        '--proto' { return 'ProtocolList' }
        '--proto-redir' { return 'ProtocolList' }
        '--proto-default' { return 'Protocol' }
        '--proxy' { return 'ProxyUrl' }
        '--preproxy' { return 'ProxyUrl' }
        '--proxy1.0' { return 'ProxyUrl' }
        '--url' { return 'Url' }
        '--doh-url' { return 'Url' }
        '--ipfs-gateway' { return 'Url' }
        '--cert-type' { return 'CertType' }
        '--proxy-cert-type' { return 'CertType' }
        '--key-type' { return 'KeyType' }
        '--proxy-key-type' { return 'KeyType' }
        '--delegation' { return 'Delegation' }
        '--ftp-method' { return 'FtpMethod' }
        '--ftp-ssl-ccc-mode' { return 'FtpSslCccMode' }
        '--tlsauthtype' { return 'TlsAuthType' }
        '--proxy-tlsauthtype' { return 'TlsAuthType' }
        '--tls-max' { return 'TlsVersion' }
        '--create-file-mode' { return 'FileMode' }
        '--upload-flags' { return 'UploadFlags' }
        '--krb' { return 'KerberosLevel' }
        '--variable' { return 'VariableSpec' }
        '-d' { return 'DataValue' }
        '--data' { return 'DataValue' }
        '--data-ascii' { return 'DataValue' }
        '--data-binary' { return 'DataValue' }
        '-H' { return 'HeaderOrFile' }
        '--header' { return 'HeaderOrFile' }
        '--proxy-header' { return 'HeaderOrFile' }
        '-b' { return 'CookieValue' }
        '--cookie' { return 'CookieValue' }
        '-E' { return 'CertificatePath' }
        '--cert' { return 'CertificatePath' }
        '--proxy-cert' { return 'CertificatePath' }
    }

    switch ($placeholderKey) {
        'subject' { return 'HelpSubject' }
        'protocols' { return 'ProtocolList' }
        'protocol' { return 'Protocol' }
        'url' { return 'Url' }
        'url/file' { return 'Url' }
        '[protocol://]host[:port]' { return 'ProxyUrl' }
        'header/@file' { return 'HeaderOrFile' }
        '[%]name=text/@file' { return 'VariableSpec' }
        'data|filename' { return 'DataOrFilename' }
        'file' { return 'FilePath' }
        'filename' { return 'FilePath' }
        'key' { return 'FilePath' }
        'dir' { return 'DirectoryPath' }
        'path' { return 'Path' }
        'certificate[:password]' { return 'CertificatePath' }
        'cert[:passwd]' { return 'CertificatePath' }
        'type' { return 'Text' }
        'version' { return 'TlsVersion' }
        'seconds' { return 'Number' }
        'ms' { return 'Number' }
        'num' { return 'Number' }
        'integer' { return 'Number' }
        'bytes' { return 'Number' }
        'offset' { return 'Number' }
        'priority' { return 'Number' }
        'value' { return 'Number' }
        'speed' { return 'Number' }
    }

    if ($placeholderKey -match '^(?:host\[:port\]|host1:port1:host2:port2|address|addresses|range|user:password|token|name|method|command|config|string|format|time|opt=val|hashes|options|data|identity|interface|ip|level|list|phrase)$') {
        return 'Text'
    }

    $null
}

function Add-CurlOptionSpec {
    param(
        [string]$Token,
        [string]$Description,
        [string]$ValuePlaceholder
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return
    }

    $catalog = Get-CurlCompletionCatalog
    $key = $Token.ToLowerInvariant()
    if ($catalog.OptionByToken.ContainsKey($key)) {
        return
    }

    $displayText = if ([string]::IsNullOrWhiteSpace($ValuePlaceholder)) {
        $Token
    } else {
        "$Token <$ValuePlaceholder>"
    }

    $catalog.OptionByToken[$key] = [pscustomobject]@{
        Token            = $Token
        DisplayText      = $displayText
        Description      = $Description
        ValuePlaceholder = $ValuePlaceholder
        ValueKind        = Get-CurlValueKind -Token $Token -Placeholder $ValuePlaceholder
    }

    $catalog.Options += $catalog.OptionByToken[$key]
}

function Initialize-CurlCompletionCatalog {
    $catalog = Get-CurlCompletionCatalog
    if ($catalog.Initialized) {
        return
    }

    $categoryLines = Invoke-CurlCapture -Arguments @('--help', 'category')
    $subjects = foreach ($line in @($categoryLines)) {
        if ($line -match '^\s*([a-z][a-z0-9-]+)\s{2,}') {
            $matches[1]
        }
    }
    $catalog.HelpSubjects = if ($subjects) {
        Get-CurlUniqueStrings -Items (@($subjects) + @(Get-CurlDefaultHelpSubjects))
    } else {
        Get-CurlDefaultHelpSubjects
    }

    $versionLines = Invoke-CurlCapture -Arguments @('--version')
    $protocolLine = $versionLines | Where-Object { $_ -like 'Protocols:*' } | Select-Object -First 1
    if ($protocolLine -and $protocolLine -match '^Protocols:\s+(.+)$') {
        $catalog.Protocols = Get-CurlUniqueStrings -Items ($matches[1] -split '\s+')
    }

    $helpLines = Invoke-CurlCapture -Arguments @('--help', 'all')
    foreach ($line in @($helpLines)) {
        if ($line -match '^\s*(?:(-\S+),\s+)?(--[A-Za-z0-9][A-Za-z0-9.\-]*)(?:\s+<([^>]+)>)?\s{2,}(.*)$') {
            $shortToken = $matches[1]
            $longToken = $matches[2]
            $valuePlaceholder = $matches[3]
            $description = $matches[4].Trim()

            if ($shortToken) {
                Add-CurlOptionSpec -Token $shortToken -Description $description -ValuePlaceholder $valuePlaceholder
            }

            Add-CurlOptionSpec -Token $longToken -Description $description -ValuePlaceholder $valuePlaceholder
        }
    }

    $catalog.Initialized = $true
}

function Get-CurlPathCompletions {
    param(
        [string]$InputPath,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly
    )

    $cleanInput = if ([string]::IsNullOrWhiteSpace($InputPath)) { '' } else { $InputPath.Trim('"') }
    $alwaysQuote = -not [string]::IsNullOrEmpty($InputPath) -and $InputPath.StartsWith('"')

    if ([string]::IsNullOrWhiteSpace($cleanInput)) {
        $parent = '.'
        $leaf = ''
    } elseif ($cleanInput.EndsWith('\') -or $cleanInput.EndsWith('/')) {
        $parent = $cleanInput
        $leaf = ''
    } else {
        $parent = Split-Path -Path $cleanInput -Parent
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '.'
        }

        $leaf = Split-Path -Path $cleanInput -Leaf
    }

    $filter = if ([string]::IsNullOrWhiteSpace($leaf)) { '*' } else { "$leaf*" }
    $items = @(Get-ChildItem -Path $parent -Filter $filter -ErrorAction SilentlyContinue)
    if ($DirectoriesOnly) {
        $items = @($items | Where-Object { $_.PSIsContainer })
    }

    foreach ($item in $items) {
        $completionText = if ($cleanInput -and -not [System.IO.Path]::IsPathRooted($cleanInput)) {
            if ($parent -eq '.') {
                $item.Name
            } else {
                Join-Path -Path $parent -ChildPath $item.Name
            }
        } else {
            $item.FullName
        }

        if ($item.PSIsContainer -and -not $completionText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $completionText += [System.IO.Path]::DirectorySeparatorChar
        }

        $completionText = ConvertTo-CurlQuotedValue -Value $completionText -AlwaysQuote $alwaysQuote
        $completionText = $Prefix + $completionText

        New-CurlCompletionResult -CompletionText $completionText -ListItemText $item.Name -ResultType 'ParameterValue' -ToolTip $item.FullName
    }
}

function New-CurlLiteralValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    if ([string]::IsNullOrWhiteSpace($CurrentValue)) {
        return @(
            New-CurlCompletionResult -CompletionText ($Prefix + $Placeholder) -ListItemText $Placeholder -ResultType 'ParameterValue' -ToolTip $ToolTip
        )
    }

    @(
        New-CurlCompletionResult -CompletionText ($Prefix + $CurrentValue) -ListItemText $CurrentValue -ResultType 'ParameterValue' -ToolTip $ToolTip
    )
}

function Get-CurlEnumValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    foreach ($value in @($Values)) {
        if ($value -like "$typedValue*") {
            New-CurlCompletionResult -CompletionText ($Prefix + $value) -ResultType 'ParameterValue' -ToolTip $ToolTip
        }
    }
}

function Get-CurlEnumOrLiteralValueResults {
    param(
        [string[]]$Values,
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $results = @(Get-CurlEnumValueResults -Values $Values -CurrentValue $CurrentValue -ToolTip $ToolTip -Prefix $Prefix)
    if ($results.Count -gt 0) {
        return $results
    }

    New-CurlLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-CurlPathValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = '',
        [switch]$DirectoriesOnly
    )

    $results = @(Get-CurlPathCompletions -InputPath $CurrentValue -Prefix $Prefix -DirectoriesOnly:$DirectoriesOnly)
    if ($results.Count -gt 0) {
        return $results
    }

    New-CurlLiteralValueResults -CurrentValue $CurrentValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-CurlUrlValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = '',
        [switch]$Proxy
    )

    $catalog = Get-CurlCompletionCatalog
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    $values = if ($Proxy) {
        @('http://', 'https://', 'socks4://', 'socks4a://', 'socks5://', 'socks5h://')
    } else {
        @($catalog.Protocols | ForEach-Object { "${_}://" })
    }

    $results = @(Get-CurlEnumValueResults -Values (Get-CurlUniqueStrings -Items $values) -CurrentValue $typedValue -ToolTip $ToolTip -Prefix $Prefix)
    if ($results.Count -gt 0) {
        return $results
    }

    New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix
}

function Get-CurlProtocolListValueResults {
    param(
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $catalog = Get-CurlCompletionCatalog
    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $basePrefix = ''
    $segment = $typedValue

    if ($typedValue -match '^(.*?,)([^,]*)$') {
        $basePrefix = $matches[1]
        $segment = $matches[2]
    }

    $modifier = ''
    $namePrefix = $segment
    if ($segment -match '^([+=-])(.*)$') {
        $modifier = $matches[1]
        $namePrefix = $matches[2]
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($value in @('all') + @($catalog.Protocols)) {
        if ($value -notlike "$namePrefix*") {
            continue
        }

        $completionText = $Prefix + $basePrefix + $modifier + $value
        [void]$results.Add((New-CurlCompletionResult -CompletionText $completionText -ResultType 'ParameterValue' -ToolTip $ToolTip))
    }

    if ($results.Count -gt 0) {
        return @($results.ToArray())
    }

    New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder '<protocols>' -ToolTip $ToolTip -Prefix $Prefix
}

function Get-CurlVariableValueResults {
    param(
        [string]$CurrentValue,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }

    if ($typedValue -match '^(.*@)([^@]*)$') {
        $variablePrefix = $matches[1]
        $pathPrefix = $matches[2]
        $results = @(Get-CurlPathCompletions -InputPath $pathPrefix -Prefix ($Prefix + $variablePrefix))
        if ($results.Count -gt 0) {
            return $results
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($typedValue) -or '%' -like "$typedValue*") {
        foreach ($envName in (Get-ChildItem Env: | Select-Object -ExpandProperty Name | Sort-Object -Unique)) {
            $candidate = "%$envName"
            if ($candidate -like "$typedValue*") {
                [void]$results.Add((New-CurlCompletionResult -CompletionText ($Prefix + $candidate) -ResultType 'ParameterValue' -ToolTip 'Import environment variable into a curl variable.'))
            }
        }
    }

    foreach ($item in @(New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder 'name=text' -ToolTip $ToolTip -Prefix $Prefix)) {
        [void]$results.Add($item)
    }

    if ([string]::IsNullOrWhiteSpace($typedValue) -or 'name@file' -like "$typedValue*") {
        [void]$results.Add((New-CurlCompletionResult -CompletionText ($Prefix + 'name@file') -ResultType 'ParameterValue' -ToolTip 'Set a curl variable from a file.'))
    }

    @($results.ToArray())
}

function Get-CurlAtFileValueResults {
    param(
        [string]$CurrentValue,
        [string]$Placeholder,
        [string]$ToolTip,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    if ($typedValue.StartsWith('@')) {
        $results = @(Get-CurlPathCompletions -InputPath $typedValue.Substring(1) -Prefix ($Prefix + '@'))
        if ($results.Count -gt 0) {
            return $results
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($typedValue) -or '@' -like "$typedValue*") {
        [void]$results.Add((New-CurlCompletionResult -CompletionText ($Prefix + '@') -ResultType 'ParameterValue' -ToolTip 'Prefix a file path with @ to load content from disk.'))
    }

    foreach ($item in @(New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder $Placeholder -ToolTip $ToolTip -Prefix $Prefix)) {
        [void]$results.Add($item)
    }

    @($results.ToArray())
}

function Get-CurlValueCompletions {
    param(
        [pscustomobject]$OptionSpec,
        [string]$CurrentValue,
        [string]$Prefix = ''
    )

    $typedValue = if ($null -eq $CurrentValue) { '' } else { $CurrentValue }
    $toolTip = if ([string]::IsNullOrWhiteSpace($OptionSpec.Description)) {
        $OptionSpec.DisplayText
    } else {
        $OptionSpec.Description
    }

    switch ($OptionSpec.ValueKind) {
        'HelpSubject' {
            return @(Get-CurlEnumOrLiteralValueResults -Values (Get-CurlCompletionCatalog).HelpSubjects -CurrentValue $typedValue -Placeholder '<subject>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Protocol' {
            return @(Get-CurlEnumOrLiteralValueResults -Values ((Get-CurlUniqueStrings -Items (@('all') + @((Get-CurlCompletionCatalog).Protocols)))) -CurrentValue $typedValue -Placeholder '<protocol>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'ProtocolList' {
            return @(Get-CurlProtocolListValueResults -CurrentValue $typedValue -ToolTip $toolTip -Prefix $Prefix)
        }
        'Url' {
            return @(Get-CurlUrlValueResults -CurrentValue $typedValue -Placeholder '<url>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'ProxyUrl' {
            return @(Get-CurlUrlValueResults -CurrentValue $typedValue -Placeholder '<proxy-url>' -ToolTip $toolTip -Prefix $Prefix -Proxy)
        }
        'DirectoryPath' {
            return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<dir>' -ToolTip $toolTip -Prefix $Prefix -DirectoriesOnly)
        }
        'FilePath' {
            return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<file>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Path' {
            return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<path>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'CertificatePath' {
            if (Test-CurlPathLikeInput -Value $typedValue) {
                return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<certificate>' -ToolTip $toolTip -Prefix $Prefix)
            }

            if ($typedValue -match '^([^:]+):(.*)$') {
                return New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder '<certificate[:password]>' -ToolTip $toolTip -Prefix $Prefix
            }

            return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<certificate>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'HeaderOrFile' {
            return @(Get-CurlAtFileValueResults -CurrentValue $typedValue -Placeholder '<header-or-@file>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'VariableSpec' {
            return @(Get-CurlVariableValueResults -CurrentValue $typedValue -ToolTip $toolTip -Prefix $Prefix)
        }
        'DataValue' {
            return @(Get-CurlAtFileValueResults -CurrentValue $typedValue -Placeholder '<data-or-@file>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'DataOrFilename' {
            if (Test-CurlPathLikeInput -Value $typedValue) {
                return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<data-or-file>' -ToolTip $toolTip -Prefix $Prefix)
            }

            return New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder '<data-or-file>' -ToolTip $toolTip -Prefix $Prefix
        }
        'CookieValue' {
            if (Test-CurlPathLikeInput -Value $typedValue) {
                return @(Get-CurlPathValueResults -CurrentValue $typedValue -Placeholder '<cookie-data-or-file>' -ToolTip $toolTip -Prefix $Prefix)
            }

            return New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder '<cookie-data-or-file>' -ToolTip $toolTip -Prefix $Prefix
        }
        'CertType' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('DER', 'PEM', 'ENG', 'PROV', 'P12') -CurrentValue $typedValue -Placeholder '<type>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'KeyType' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('DER', 'PEM', 'ENG') -CurrentValue $typedValue -Placeholder '<type>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Delegation' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('none', 'policy', 'always') -CurrentValue $typedValue -Placeholder '<level>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'FtpMethod' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('multicwd', 'nocwd', 'singlecwd') -CurrentValue $typedValue -Placeholder '<method>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'FtpSslCccMode' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('active', 'passive') -CurrentValue $typedValue -Placeholder '<mode>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'TlsAuthType' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('SRP') -CurrentValue $typedValue -Placeholder '<type>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'TlsVersion' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('default', '1.0', '1.1', '1.2', '1.3') -CurrentValue $typedValue -Placeholder '<VERSION>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'UploadFlags' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('append', 'create', 'failifexist', 'overwrite') -CurrentValue $typedValue -Placeholder '<flags>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'KerberosLevel' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('clear', 'safe', 'conf', 'cred') -CurrentValue $typedValue -Placeholder '<level>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'FileMode' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('0600', '0644', '0660', '0755') -CurrentValue $typedValue -Placeholder '<mode>' -ToolTip $toolTip -Prefix $Prefix)
        }
        'Number' {
            return @(Get-CurlEnumOrLiteralValueResults -Values @('0', '1', '5', '10', '30', '60', '300') -CurrentValue $typedValue -Placeholder '<number>' -ToolTip $toolTip -Prefix $Prefix)
        }
        default {
            return New-CurlLiteralValueResults -CurrentValue $typedValue -Placeholder ('<' + $OptionSpec.ValuePlaceholder + '>') -ToolTip $toolTip -Prefix $Prefix
        }
    }
}

function Get-CurlPendingOption {
    param([string[]]$TokensBeforeCurrent)

    Initialize-CurlCompletionCatalog
    $catalog = Get-CurlCompletionCatalog
    $pendingOption = $null

    foreach ($token in @($TokensBeforeCurrent)) {
        $cleanToken = Remove-CurlOuterQuotes -Value $token
        if ([string]::IsNullOrWhiteSpace($cleanToken)) {
            continue
        }

        if ($pendingOption) {
            $pendingOption = $null
            continue
        }

        if ($cleanToken -match '^(--[^=]+)=') {
            continue
        }

        $lookup = $cleanToken.ToLowerInvariant()
        if ($catalog.OptionByToken.ContainsKey($lookup) -and $catalog.OptionByToken[$lookup].ValueKind) {
            $pendingOption = $catalog.OptionByToken[$lookup]
        }
    }

    $pendingOption
}

function Get-CurlOptionCompletions {
    param([string]$CurrentWord)

    Initialize-CurlCompletionCatalog
    $catalog = Get-CurlCompletionCatalog
    $cleanCurrent = Remove-CurlOuterQuotes -Value $CurrentWord

    foreach ($option in $catalog.Options) {
        if ($option.Token -like "$cleanCurrent*") {
            $toolTip = if ([string]::IsNullOrWhiteSpace($option.Description)) { $option.DisplayText } else { $option.Description }
            New-CurlCompletionResult -CompletionText $option.Token -ListItemText $option.DisplayText -ResultType 'ParameterName' -ToolTip $toolTip
        }
    }
}

function Get-CurlPositionalCompletions {
    param([string]$CurrentWord)

    Initialize-CurlCompletionCatalog
    Get-CurlUrlValueResults -CurrentValue $CurrentWord -Placeholder '<url>' -ToolTip 'URL to transfer.'
}

Register-ArgumentCompleter -Native -CommandName 'curl', 'curl.exe' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    if ($wordToComplete -isnot [string]) {
        $wordToComplete = [string]$wordToComplete
    }

    Initialize-CurlCompletionCatalog

    $currentToken = Get-CurlCurrentToken -Line $commandAst.Extent.Text -CursorPosition $cursorPosition -Fallback $wordToComplete
    $tokensBeforeCurrent = Get-CurlArgumentTokens -CommandAst $commandAst -CursorPosition $cursorPosition

    if ($currentToken -match '^(--[^=]+)=(.*)$') {
        $optionKey = $matches[1].ToLowerInvariant()
        $valuePrefix = $matches[2]
        $catalog = Get-CurlCompletionCatalog
        if ($catalog.OptionByToken.ContainsKey($optionKey)) {
            $optionSpec = $catalog.OptionByToken[$optionKey]
            if ($optionSpec.ValueKind) {
                return @(Get-CurlValueCompletions -OptionSpec $optionSpec -CurrentValue $valuePrefix -Prefix ($matches[1] + '='))
            }
        }
    }

    $pendingOption = Get-CurlPendingOption -TokensBeforeCurrent $tokensBeforeCurrent
    if ($pendingOption) {
        return @(Get-CurlValueCompletions -OptionSpec $pendingOption -CurrentValue $wordToComplete)
    }

    $results = New-Object System.Collections.Generic.List[System.Management.Automation.CompletionResult]

    if ([string]::IsNullOrWhiteSpace($currentToken) -or $currentToken.StartsWith('-')) {
        foreach ($result in @(Get-CurlOptionCompletions -CurrentWord $wordToComplete)) {
            [void]$results.Add($result)
        }
    }

    if (-not $currentToken.StartsWith('-')) {
        foreach ($result in @(Get-CurlPositionalCompletions -CurrentWord $wordToComplete)) {
            [void]$results.Add($result)
        }
    }

    @($results.ToArray())
}

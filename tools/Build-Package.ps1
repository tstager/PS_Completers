#Requires -Version 7.0

<#
.SYNOPSIS
Stages the PS_Completers package folder for Publish-PSResource.

.DESCRIPTION
Builds <DestinationPath>/PS_Completers/ as a CompleterActions completer-set
package:

    PS_Completers/
      PS_Completers.psd1    module manifest, from package/PS_Completers.psd1
      LICENSE
      README.md
      completers/
        completers.psd1     ps_completers.psd1, copied byte for byte
        <name>_completer/   every *_completer folder

The set is renamed because PSResourceGet reads a .psd1 whose base name equals
the module name, in any folder of the package, as the module manifest, so a
package named PS_Completers holding ps_completers.psd1 cannot be saved or
installed. The set and the *_completer folders keep their positions relative to
each other, so the set's relative paths and hashes hold in the staged copy.

Only the files above are staged. Publish-PSResource packs the whole folder it
is given, so tests, tools, .github, docs, package, .claude, and every other
repository file stay out of the package.

The tool fails if <DestinationPath>/PS_Completers already exists, so a staged
package never mixes with an older one.

.PARAMETER DestinationPath
The folder to stage into. It is created if missing. The package is written to
its PS_Completers subfolder, which must not exist yet.

.EXAMPLE
pwsh -NoProfile -File ./tools/Build-Package.ps1 -DestinationPath ./out
Test-CompleterSet -LiteralPath ./out/PS_Completers/completers/completers.psd1

Stages the package into ./out/PS_Completers and checks the staged set; the
check prints nothing for a package ready to publish.

.OUTPUTS
System.IO.DirectoryInfo. The staged PS_Completers folder.
#>
[CmdletBinding()]
[OutputType([System.IO.DirectoryInfo])]
param(
    [Parameter(Mandatory)]
    [string] $DestinationPath
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$package = Join-Path -Path $DestinationPath -ChildPath 'PS_Completers'
$completers = Join-Path -Path $package -ChildPath 'completers'

if (Test-Path -LiteralPath $package) {
    throw "The package folder '$package' already exists. Remove it or choose another destination."
}

New-Item -Path $completers -ItemType Directory -Force | Out-Null

Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'package/PS_Completers.psd1'),
    (Join-Path -Path $repoRoot -ChildPath 'LICENSE'),
    (Join-Path -Path $repoRoot -ChildPath 'README.md') -Destination $package
Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'ps_completers.psd1') -Destination (Join-Path -Path $completers -ChildPath 'completers.psd1')
Get-ChildItem -LiteralPath $repoRoot -Directory -Filter '*_completer' | Copy-Item -Destination $completers -Recurse

Get-Item -LiteralPath $package

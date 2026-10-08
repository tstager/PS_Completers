#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
Path-quoting gate for the completers that complete file system paths.

.DESCRIPTION
Each probe loads one completer script into its own runspace, moves that runspace into a
test-drive folder of hostile file names, and runs TabExpansion2 at a line prefix that puts
the cursor in a path slot: once as typed, once after a typed single quote, and once after
a typed double quote. Every candidate is accepted the way PSReadLine accepts it (the line
up to ReplacementIndex plus CompletionText) and the result must parse as one command with
exactly one new argument. A candidate whose list text names a fixture (after any quotes,
directories, '--option=', '/X:' or '@' in front of it) must also produce that name as a
constant string argument: no variable expansion, no array literal, no lost or doubled
backtick, no stray quote. Option and placeholder candidates only have to parse.

A completer that returns nothing leaves PowerShell's own file name completion in place, so
a probe still passes where the native tool is missing; the gate needs no tool installed.
Some slots are only known once the tool's help has been parsed (oh-my-posh --config, pip,
pnpm, rustup override --path); without the tool those probes check the engine fallback.
Prefixes that end in './' or '@' are for completers that only list files once a path-like
word (or an @file list) has been typed. No row is skipped on Linux: Windows-only completers
either run their path code there too or return nothing and leave the engine fallback.

[System.Management.Automation.CompletionCompleters]::CompleteFilename doubles a backtick
inside single quotes ('.\tick``x.txt' names tick``x.txt), so a completer that hands its
results through unchanged fails here on the tick`x.txt fixture.

Completers whose scripts touch the file system but have no path slot to probe:
- gh_cli, uv: path-valued options return nothing on purpose so the engine completes them.
- listdlls: only offers DLL names from the system directory for -d.
- npm: only reads node_modules for installed package names.
- printenv: only lists the Env: drive.
- psfile, psservice, tasklist, false, nproc: no file system completion at all.
- regjump, RegDelNull: complete registry keys, not files.
- wsl, wslconfig: read distribution names from the registry; path options return nothing.
- wt: only reads Windows Terminal's settings.json for profile and scheme names.

Run it in its own profile-free process:

    pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/PathQuoting.Tests.ps1 -Output Detailed"
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent

    # Completer folder name -> line prefixes that leave the cursor in a path slot.
    $probes = [ordered]@{
        '7z'               = '7z a ', '7z x '
        'accesschk'        = 'accesschk '
        'agy'              = 'agy --add-dir ', 'agy --log-file '
        'apm'              = 'apm unpack ', 'apm pack -o ', 'apm audit --file '
        'attrib'           = 'attrib '
        'autorunsc'        = 'autorunsc -o '
        'base32'           = 'base32 '
        'base64'           = 'base64 '
        'basename'         = 'basename '
        'bun'              = 'bun '
        'cargo'            = 'cargo -C ', 'cargo new ', 'cargo build --target-dir ', 'cargo build --manifest-path '
        'cargo_binstall'   = 'cargo-binstall --root ', 'cargo-binstall --manifest-path '
        'cargo_clippy'     = 'cargo-clippy --manifest-path ', 'cargo-clippy --target-dir '
        'cksum'            = 'cksum '
        'claude'           = 'claude --add-dir ', 'claude --mcp-config ', 'claude purge '
        'cmd'              = 'cmd ./', 'cmd /c dir ./'
        'code_insiders'    = 'code-insiders --add ', 'code-insiders --diff '
        'codex'            = 'codex --cd ', 'codex --add-dir '
        'comfy_cli'        = 'comfy-cli --workspace ', 'comfy-cli upload '
        'comm'             = 'comm '
        'compact'          = 'compact '
        'contig'           = 'contig '
        'copilot'          = 'copilot -C ', 'copilot --attachment '
        'csplit'           = 'csplit '
        'curl'             = 'curl -o ', 'curl --output=', 'curl -d @'
        'cursor_agent'     = 'cursor-agent --workspace ', 'cursor-agent --add-dir '
        'cut'              = 'cut '
        'date'             = 'date '
        'dd'               = 'dd if=', 'dd of='
        'df'               = 'df '
        'dircolors'        = 'dircolors '
        'dirname'          = 'dirname '
        'dism'             = 'dism ./', 'dism /ImageFile:'
        'docker'           = 'docker --config ', 'docker --tlscert '
        'dotnet'           = 'dotnet '
        'DSC'              = 'dsc config get --file='
        'du'               = 'du '
        'env'              = 'env -C ', 'env --chdir='
        'fd'               = 'fd --ignore-file '
        'findstr'          = 'findstr foo ', 'findstr /F:'
        'fmt'              = 'fmt '
        'fold'             = 'fold '
        'fsutil'           = 'fsutil 8dot3name scan ', 'fsutil file createNew '
        'gawk'             = 'gawk -f ', 'gawk --file='
        'Git'              = 'git -C ', 'git config --file ', 'git diff -- '
        'go'               = 'go -C ', 'go build ', 'go work use '
        'groff'            = 'groff '
        'grok'             = 'grok --cwd ', 'grok --debug-file '
        'handle'           = 'handle '
        'head'             = 'head '
        'icacls'           = 'icacls '
        'join'             = 'join '
        'jq'               = 'jq . '
        'link'             = 'link '
        'ln'               = 'ln '
        'markitdown'       = 'markitdown '
        'md5sum'           = 'md5sum '
        'mktemp'           = 'mktemp -p ', 'mktemp --tmpdir='
        'netsh'            = 'netsh -f ', 'netsh -a '
        'nl'               = 'nl '
        'od'               = 'od '
        'OhMyPosh'         = 'oh-my-posh init pwsh --config '
        'ollama'           = 'ollama create -f '
        'onemd'            = 'onemd import ', 'onemd --config-dir ', 'onemd export -o '
        'opencode'         = 'opencode ', 'opencode run --file ', 'opencode attach --dir '
        'paste'            = 'paste '
        'pathchk'          = 'pathchk ./'
        'pi'               = 'pi --export ', 'pi --mcp-config '
        'pip'              = 'pip install --requirement=', 'pip --log='
        'playwright_cli'   = 'playwright-cli upload ', 'playwright-cli state-load '
        'pnpm'             = 'pnpm --npmrc-auth-file ', 'pnpm -C '
        'pr'               = 'pr '
        'printf'           = 'printf '
        'procdump'         = 'procdump -x ', 'procdump -md '
        'psexec'           = 'psexec -c ', 'psexec ./', 'psexec @'
        'psgetsid'         = 'psgetsid @'
        'psinfo'           = 'psinfo @'
        'psloglist'        = 'psloglist -l '
        'psmux'            = 'psmux -f ', 'psmux source-file '
        'pspasswd'         = 'pspasswd @'
        'psshutdown'       = 'psshutdown @'
        'ptx'              = 'ptx '
        'pwsh'             = 'pwsh '
        'py'               = 'py '
        'python'           = 'python '
        'qwen'             = 'qwen --add-dir ', 'qwen extensions link '
        'readlink'         = 'readlink '
        'realpath'         = 'realpath '
        'reg'              = 'reg IMPORT ', 'reg EXPORT HKCU\ ', 'reg LOAD HKLM\ '
        'rg'               = 'rg --ignore-file ', 'rg foo '
        'robocopy'         = 'robocopy ', 'robocopy src '
        'rtk'              = 'rtk ls ', 'rtk read '
        'ru'               = 'ru -h '
        'rustc'            = 'rustc '
        'rustfmt'          = 'rustfmt '
        'rustup'           = 'rustup toolchain link foo ', 'rustup override set --path '
        'sbx'              = 'sbx run ', 'sbx create '
        'sc'               = 'sc create svc binPath= '
        'schtasks'         = 'schtasks /Create /XML ', 'schtasks /Create /TR '
        'scoop'            = 'scoop install ./', 'scoop config cache_path ./'
        'sdelete'          = 'sdelete '
        'sed'              = 'sed -f '
        'sha1sum'          = 'sha1sum '
        'sha224sum'        = 'sha224sum '
        'sha256sum'        = 'sha256sum '
        'sha384sum'        = 'sha384sum '
        'sha512sum'        = 'sha512sum '
        'shellrunas'       = 'shellrunas ./'
        'shred'            = 'shred '
        'shuf'             = 'shuf '
        'sigcheck'         = 'sigcheck '
        'split'            = 'split '
        'stat'             = 'stat '
        'stdbuf'           = 'stdbuf ./', 'stdbuf -oL cat ./'
        'strings'          = 'strings '
        'sum'              = 'sum '
        'tac'              = 'tac '
        'tail'             = 'tail '
        'takeown'          = 'takeown /F '
        'tar'              = 'tar -f ', 'tar --file=', 'tar -cf x.tar '
        'test'             = 'test '
        'touch'            = 'touch '
        'tr'               = 'tr a b '
        'truncate'         = 'truncate '
        'tsort'            = 'tsort '
        'unexpand'         = 'unexpand '
        'uniq'             = 'uniq '
        'unlink'           = 'unlink '
        'uptime'           = 'uptime '
        'vdir'             = 'vdir '
        'wc'               = 'wc '
        'wecutil'          = 'wecutil cs '
        'wevtutil'         = 'wevtutil im ', 'wevtutil al '
        'where'            = 'where.exe /R '
        'winapp'           = 'winapp init ', 'winapp run ', 'winapp new --output '
        'wpr'              = 'wpr -merge ', 'wpr -profiles '
        'wsb'              = 'wsb share -f '
        'wslc'             = 'wslc load --input ', 'wslc build '
        'xargs'            = 'xargs -a ', 'xargs --arg-file='
        'xcopy'            = 'xcopy '
        'zip'              = 'zip '
    }

    # Ratchet: completers that failed this gate when it was added (2026-10-07). Each one is still
    # probed; while it fails it is reported as skipped, and once it passes the test fails until
    # its name is removed here, so this list only ever shrinks. Never add a name to it.
    $knownFailures = @(
        'accesschk', 'agy', 'autorunsc', 'base32', 'base64', 'basename', 'bun', 'cargo',
        'cargo_binstall', 'cargo_clippy', 'claude', 'code_insiders', 'comfy_cli', 'comm', 'compact', 'contig',
        'copilot', 'csplit', 'curl', 'cut', 'date', 'dd', 'df', 'dirname',
        'docker', 'DSC', 'env', 'fd', 'findstr', 'fmt', 'fsutil', 'gawk',
        'Git', 'go', 'groff', 'grok', 'head', 'icacls', 'join', 'jq',
        'link', 'ln', 'nl', 'od', 'OhMyPosh', 'ollama', 'onemd', 'opencode',
        'pi', 'pip', 'playwright_cli', 'pnpm', 'pr', 'psgetsid', 'psinfo', 'psmux',
        'pspasswd', 'psshutdown', 'ptx', 'pwsh', 'py', 'python', 'qwen', 'realpath',
        'rtk', 'rustup', 'sc', 'scoop', 'sdelete', 'sed', 'sha224sum', 'sha256sum',
        'sha512sum', 'shuf', 'stat', 'stdbuf', 'strings', 'sum', 'tail', 'tar',
        'test', 'tr', 'truncate', 'tsort', 'unexpand', 'uniq', 'unlink', 'uptime',
        'wc', 'winapp', 'wpr', 'wslc', 'xargs', 'xcopy', 'zip'
    )

    $script:pathProbes = @(
        foreach ($name in $probes.Keys) {
            @{
                Name         = $name
                Path         = Join-Path -Path $repoRoot -ChildPath "${name}_completer/${name}_completer.ps1"
                Prefixes     = @($probes[$name])
                Label        = (@($probes[$name] | ForEach-Object { "[$_]" }) -join ' ')
                KnownFailure = $knownFailures -ccontains $name
            }
        }
    )
}

Describe 'Path completions survive hostile file names' {
    BeforeAll {
        $script:FixturePath = Join-Path -Path $TestDrive -ChildPath 'hostile'
        $script:FixtureNames = @(
            'sp ace.txt'
            'a$b.txt'
            'amp&c.txt'
            'semi;c.txt'
            "it's.txt"
            "it$([char]0x2019)s q.txt"
            'pa(r).txt'
            'br{a}.txt'
            'tick`x.txt'
            'comma,x.txt'
            'sub dir&x'
        )

        # [IO.File] and [IO.Directory] take names literally; New-Item -Path would read [ ] as wildcards.
        $null = [System.IO.Directory]::CreateDirectory($script:FixturePath)
        foreach ($name in $script:FixtureNames | Select-Object -SkipLast 1) {
            [System.IO.File]::WriteAllText((Join-Path -Path $script:FixturePath -ChildPath $name), '')
        }
        $null = [System.IO.Directory]::CreateDirectory((Join-Path -Path $script:FixturePath -ChildPath $script:FixtureNames[-1]))

        function Get-CandidateProblem {
            # Accepts one candidate and returns what is wrong with the line it produces, if anything.
            param(
                [string]$Line,
                [int]$ReplacementIndex,
                [System.Management.Automation.CompletionResult]$Candidate
            )

            $head = $Line.Substring(0, $ReplacementIndex)
            $accepted = $head + $Candidate.CompletionText

            # A candidate that leaves the typed line unchanged inserts nothing, and a <placeholder>
            # hint is meant to be typed over (repo convention); neither can break a path.
            if ($accepted -ceq $Line -or $Candidate.CompletionText -match '<[^<>\s]+>') {
                return
            }

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($accepted, [ref]$tokens, [ref]$errors)
            if ($errors.Count -gt 0) {
                return "parse error: $(($errors | ForEach-Object Message) -join ' / ')"
            }

            $statements = $ast.EndBlock.Statements
            $pipeline = $statements | Select-Object -First 1
            if ($statements.Count -ne 1 -or $pipeline -isnot [System.Management.Automation.Language.PipelineAst] -or
                $pipeline.Background -or $pipeline.PipelineElements.Count -ne 1 -or
                $pipeline.PipelineElements[0] -isnot [System.Management.Automation.Language.CommandAst]) {
                return "does not parse as one command (statements: $($statements.Count))"
            }

            $command = $pipeline.PipelineElements[0]
            if ($command.Redirections.Count -gt 0) {
                return 'parses with a redirection'
            }

            $headAst = [System.Management.Automation.Language.Parser]::ParseInput($head, [ref]$null, [ref]$null)
            $headCommand = $headAst.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
            $expectedCount = $headCommand.CommandElements.Count + 1
            if ($command.CommandElements.Count -ne $expectedCount) {
                return "parses as $($command.CommandElements.Count - $expectedCount + 1) arguments, not 1"
            }

            # The list text may itself be quoted or carry a directory, '--option=', '/X:' or '@' in front.
            $listed = $Candidate.ListItemText
            if ($listed -match ('^[''"' + [char]0x2018 + '-' + [char]0x201E + ']')) {
                $listTokens = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($listed, [ref]$listTokens, [ref]$null)
                $listed = [string]$listTokens[0].Value
            }
            $leaf = ($listed.Trim('"', "'").TrimEnd('\', '/') -split '[\\/=:]')[-1].Trim('"', "'").TrimStart('@')
            if ($script:FixtureNames -cnotcontains $leaf) {
                return
            }

            $argument = $command.CommandElements[-1]
            if ($argument -is [System.Management.Automation.Language.CommandParameterAst]) {
                $argument = $argument.Argument
            }
            if ($argument -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return "the argument for '$leaf' is a $($argument.GetType().Name), not a constant string"
            }

            $value = ([string]$argument.SafeGetValue()).TrimEnd('\', '/')
            $namesLeaf = $value.EndsWith($leaf, [System.StringComparison]::Ordinal) -and
                ($value.Length -eq $leaf.Length -or $value[$value.Length - $leaf.Length - 1] -in '\', '/', '=', ':', '@')
            if (-not $namesLeaf) {
                return "the argument value <$value> does not name '$leaf'"
            }
        }

        function Get-ProbeProblem {
            # Loads one completer into its own runspace and returns every broken accepted line.
            param(
                [string]$Path,
                [string[]]$Prefixes
            )

            $problems = [System.Collections.Generic.List[string]]::new()
            $shell = [powershell]::Create()
            try {
                $null = $shell.AddScript('param($Path) . $Path').AddArgument($Path).Invoke()

                foreach ($prefix in $Prefixes) {
                    foreach ($typed in '', "'", '"') {
                        $line = $prefix + $typed
                        $shell.Commands.Clear()
                        $completion = $shell.AddScript(
                            'param($Directory, $Line) Set-Location -LiteralPath $Directory; TabExpansion2 -inputScript $Line -cursorColumn $Line.Length'
                        ).AddArgument($script:FixturePath).AddArgument($line).Invoke() | Select-Object -First 1

                        foreach ($candidate in $completion.CompletionMatches) {
                            $problem = Get-CandidateProblem -Line $line -ReplacementIndex $completion.ReplacementIndex -Candidate $candidate
                            if ($problem) {
                                $problems.Add("[$line] + [$($candidate.CompletionText)] -> $problem")
                            }
                        }
                    }
                }
            }
            finally {
                $shell.Dispose()
            }

            , $problems
        }
    }

    It '<Name> quotes every candidate at <Label>' -ForEach ($pathProbes | Where-Object { -not $_.KnownFailure }) {
        $problems = Get-ProbeProblem -Path $Path -Prefixes $Prefixes
        $problems.Count | Should -Be 0 -Because ("every accepted candidate must parse to its own argument:`n" + ($problems -join "`n") + "`n")
    }

    It '<Name> is still a known path-quoting failure at <Label>' -ForEach ($pathProbes | Where-Object { $_.KnownFailure }) {
        $problems = Get-ProbeProblem -Path $Path -Prefixes $Prefixes
        if ($problems.Count -eq 0 -and -not $IsWindows) {
            # Off Windows some listed completers never reach their path code (no native tool), so a
            # pass here proves nothing; the list is ratcheted by the Windows run.
            Set-ItResult -Skipped -Because 'passes off Windows only because the path code is not reached'
            return
        }
        $problems.Count | Should -BeGreaterThan 0 -Because "$Name now passes: remove it from `$knownFailures in this file so the gate enforces it"
        Set-ItResult -Skipped -Because "known path-quoting failure ($($problems.Count) broken candidates): $($problems[0])"
    }
}

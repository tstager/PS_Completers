<#
.SYNOPSIS
    Argument completer for qwen / qwen.cmd / qwen.ps1.
.DESCRIPTION
    Provides tab completion for qwen subcommands, flags, flag values, and the
    --flag=value inline syntax.  Dot-source this file from your $PROFILE to
    enable completion for all three invocation forms.

    Safe to source multiple times (re-registration simply replaces the completer).
.EXAMPLE
    . "$PSScriptRoot\qwen_completer.ps1"
#>

Set-StrictMode -Version Latest

function Initialize-QwenCompleterData {
    if (Get-Variable -Name QwenTopCommands -Scope Script -ErrorAction Ignore) {
        return
    }

    # Top-level subcommands, in upstream registration order (config.ts; 'review' is
    # registered lazily whenever argv contains it, so it is always reachable).
    $script:QwenTopCommands = @('mcp', 'extensions', 'auth', 'hooks', 'hook', 'channel', 'board', 'serve',
                                'sessions', 'batch', 'update', 'sandbox', 'review')

    # Level-2 subcommands per top-level command.
    $script:QwenSubSubcommands = @{
        mcp        = @('add', 'remove', 'list', 'reconnect', 'approve', 'reject')
        extensions = @('install', 'uninstall', 'list', 'update', 'disable', 'enable', 'link', 'new',
                       'settings', 'sources')
        auth       = @('status', 'coding-plan', 'openrouter', 'requesty', 'api-key', 'qwen-oauth')
        channel    = @('start', 'daemon-worker', 'stop', 'status', 'reload', 'set', 'pairing', 'configure-weixin')
        board      = @('show', 'task', 'claim', 'done', 'ask', 'answer', 'decline', 'prune')
        sessions   = @('list', 'ps', 'controllers')
        batch      = @('run', 'collect', 'retry', 'cancel', 'list', 'check', 'clean')
        review     = @('run', 'parse-args', 'match-remote', 'meta', 'issue-context', 'fetch-diff',
                       'comment-body', 'fetch-pr', 'capture-local', 'capture-tui', 'plan-diff',
                       'cache-commit', 'repo-context', 'pr-context', 'comment-status', 'load-rules',
                       'agent-prompt', 'emit-workflow', 'build-test', 'base-tree', 'scratch-tree',
                       'test-delta', 'fix-delta', 'drive', 'ab-drive', 'mock-provider', 'extract-step',
                       'script-lint', 'dedup-candidates', 'revert-hunk', 'resolve-anchors',
                       'check-coverage', 'cost-ledger', 'presubmit', 'test-efficacy', 'test-plan',
                       'findings', 'recover-findings', 'publish-assets', 'compose-review',
                       'save-artifact', 'submit', 'cleanup')
        hooks      = @()
        hook       = @()
        serve      = @()
        update     = @()
        sandbox    = @()
    }

    # Level-3 subcommands: "cmd.subcmd" -> @(subsubcmds).
    $script:QwenL3Subcommands = @{
        'extensions.settings'  = @('set', 'list')
        'extensions.sources'   = @('add', 'remove', 'list', 'update')
        'channel.pairing'      = @('list', 'approve')
        'sessions.controllers' = @('add', 'list', 'remove')
    }

    # Commands that are parsed but never offered: 'auth' and its legacy subcommands
    # only print "qwen auth has been removed.", and 'channel daemon-worker' is
    # declared with describe: false (internal).
    $script:QwenHiddenCommands = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('auth', 'channel.daemon-worker'), [System.StringComparer]::Ordinal
    )
    foreach ($legacy in $script:QwenSubSubcommands.auth) { $null = $script:QwenHiddenCommands.Add("auth.$legacy") }

    # ---- Flag categories -----------------------------------------------------------------------

    # Global enum flags with fixed choice sets.
    $script:QwenEnumFlags = @{
        '--telemetry-target'        = @('local', 'gcp')
        '--telemetry-otlp-protocol' = @('grpc', 'http')
        # 'auto' precedes 'auto-edit' so Tab on a typed 'auto' keeps it.
        '--approval-mode'           = @('plan', 'default', 'auto', 'auto-edit', 'yolo')
        '--channel'                 = @('VSCode', 'ACP', 'SDK', 'CI', 'desktop', 'daemon')
        '--input-format'            = @('text', 'stream-json')
        '--output-format'           = @('text', 'json', 'stream-json')
        '--auth-type'               = @('openai', 'openai-responses', 'anthropic', 'qwen-oauth', 'gemini', 'vertex-ai')
        '--sandbox'                 = @('true', 'false', 'docker', 'podman', 'sandbox-exec')   # [string], NOT a switch
    }

    # Boolean / switch flags (accept no value).
    $script:QwenBoolFlags = @(
        '--telemetry'
        '--telemetry-log-prompts'
        '--debug'
        '--bare'
        '--safe-mode'
        '--insecure'
        '--chat-recording'
        '--yolo'
        '--acp'
        '--experimental-lsp'
        '--restore-ask-user-question'
        '--openai-logging'
        '--screen-reader'
        '--include-partial-messages'
        '--list-extensions'
        '--continue'
        '--fork-session'
        '--help'
        '--version'
    )

    # Free-form string flags (single value, no fixed choices).
    $script:QwenStringFlags = @(
        '--telemetry-otlp-endpoint'
        '--proxy'
        '--model'
        '--advisor'
        '--prompt'
        '--prompt-interactive'
        '--system-prompt'
        '--append-system-prompt'
        '--output-style'
        '--sandbox-image'
        '--openai-api-key'
        '--openai-base-url'
        '--json-schema'
        '--resume'
        '--session-id'
        '--worktree'
        '--max-wall-time'
    )

    # Numeric flags.
    $script:QwenNumberFlags = @(
        '--max-session-turns'
        '--json-fd'
        '--max-tool-calls'
        '--max-subagent-depth'
    )

    # Array / multi-value flags.
    $script:QwenArrayFlags = @(
        '--fallback-model'
        '--allowed-mcp-server-names'
        '--allowed-tools'
        '--extensions'
        '--include-directories'
        '--add-dir'          # alias for --include-directories (help: --include-directories, --add-dir)
        '--core-tools'
        '--exclude-tools'
        '--disabled-slash-commands'
    )

    # Flags that produce file-path completion.
    $script:QwenPathFlags = @(
        '--telemetry-outfile'
        '--mcp-config'
        '--json-file'
        '--input-file'
    )

    # Flags that produce directory-path completion.
    $script:QwenDirFlags = @(
        '--openai-logging-dir'
        '--include-directories'
        '--add-dir'
    )

    # ---- Context tables ------------------------------------------------------------------------
    # A context is a command path: 'serve', 'mcp.add', 'sessions.controllers.add'.  yargs
    # options are global, so a command's options also apply to its subcommands: lookups walk
    # from the deepest context up to its top-level command, and the first declaration wins
    # (it also shadows a global flag of the same name, e.g. 'review run --resume').

    # Value-taking options declared by a command: context -> @(flags).
    $script:QwenContextFlags = @{
        'mcp.add'                     = @('--scope', '--transport', '--env', '--header', '--timeout',
                                          '--description', '--include-tools', '--exclude-tools',
                                          '--oauth-client-id', '--oauth-client-secret', '--oauth-redirect-uri',
                                          '--oauth-authorization-url', '--oauth-token-url', '--oauth-scopes')
        'extensions.install'          = @('--ref', '--registry', '--scope')
        'extensions.disable'          = @('--scope')
        'extensions.enable'           = @('--scope')
        'extensions.settings.set'     = @('--scope')
        'channel.daemon-worker'       = @('--channel')
        'channel.reload'              = @('--daemon-url', '--token', '--timeout')
        'channel.set'                 = @('--daemon-url', '--token', '--timeout')
        'board'                       = @('--board', '--as')
        'board.task'                  = @('--owner')
        'board.done'                  = @('--note')
        'board.ask'                   = @('--about', '--timeout', '--ttl')
        'board.prune'                 = @('--older-than')
        'sessions.list'               = @('--limit')
        'sessions.controllers.add'    = @('--label')
        'batch.run'                   = @('--expect')
        'batch.collect'               = @('--timeout')
        'batch.retry'                 = @('--max-output-tokens')
        'sandbox'                     = @('--sandbox')
        'serve'                       = @('--port', '--hostname', '--profile', '--hosted-harness-capability-digest',
                                          '--token', '--max-sessions', '--max-total-sessions',
                                          '--max-pending-prompts-per-session', '--workspace',
                                          '--memory-project-scope', '--max-connections', '--tls-cert', '--tls-key',
                                          '--channel', '--local-control-address', '--join', '--agent-host-server',
                                          '--agent-host-workspace-id', '--agent-host-name', '--event-ring-size',
                                          '--compacted-replay-max-bytes', '--max-journal-events',
                                          '--max-journal-bytes', '--memory-budget-mb', '--memory-pressure-mode',
                                          '--child-heap-mode', '--mcp-client-budget', '--mcp-budget-mode',
                                          '--allow-origin', '--prompt-deadline-ms',
                                          '--experimental-managed-runtime-url',
                                          '--experimental-managed-runtime-token', '--managed-runtime-broker-url',
                                          '--managed-runtime-broker-token', '--writer-idle-timeout-ms',
                                          '--channel-idle-timeout-ms', '--initialize-timeout-ms',
                                          '--session-restore-timeout-ms', '--session-reap-interval-ms',
                                          '--session-idle-timeout-ms', '--session-prompt-settled-close-grace-ms',
                                          '--permission-response-timeout-ms', '--external-tool-guard-mode',
                                          '--external-tool-guard-endpoint', '--external-tool-guard-timeout-ms',
                                          '--rate-limit-prompt', '--rate-limit-mutation', '--rate-limit-read',
                                          '--rate-limit-window-ms')
        'review.ab-drive'             = @('--script', '--arm-a', '--arm-b', '--ready', '--ready-timeout',
                                          '--timeout', '--shared', '--shared-ready', '--shared-ready-timeout',
                                          '--shared-cwd', '--server', '--out')
        'review.agent-prompt'         = @('--plan', '--role', '--chunk', '--file', '--rules', '--findings',
                                          '--hunks', '--round')
        'review.base-tree'            = @('--plan', '--worktree', '--out', '--timeout')
        'review.build-test'           = @('--plan', '--worktree', '--out', '--timeout', '--budget')
        'review.cache-commit'         = @('--candidate', '--ledger', '--out', '--state-id')
        'review.capture-local'        = @('--out', '--file', '--target', '--effort', '--deadline', '--cache')
        'review.capture-tui'          = @('--command', '--cwd', '--cols', '--rows', '--settle-ms', '--until',
                                          '--ready', '--keys', '--out', '--timeout-ms')
        'review.check-coverage'       = @('--plan', '--out')
        'review.comment-body'         = @('--kind', '--pr', '--repo', '--host', '--out')
        'review.comment-status'       = @('--out', '--host')
        'review.compose-review'       = @('--input', '--comments', '--out', '--host', '--pr', '--repo',
                                          '--skill-args')
        'review.cost-ledger'          = @('--plan', '--out')
        'review.dedup-candidates'     = @('--plan', '--candidates')
        'review.drive'                = @('--script', '--cwd', '--ready', '--ready-timeout', '--timeout',
                                          '--server', '--capture', '--out')
        'review.emit-workflow'        = @('--plan', '--rules', '--batch')
        'review.extract-step'         = @('--workflow', '--job', '--step', '--out')
        'review.fetch-diff'           = @('--repo', '--host', '--out')
        'review.fetch-pr'             = @('--remote', '--out', '--host', '--max-chunk-lines', '--effort',
                                          '--deadline', '--since', '--since-model')
        'review.findings'             = @('--input', '--out', '--outcomes', '--test-delta', '--to-anchors')
        'review.fix-delta'            = @('--since', '--out')
        'review.issue-context'        = @('--repo', '--host', '--issue', '--out')
        'review.load-rules'           = @('--out')
        'review.match-remote'         = @('--owner', '--repo', '--host', '--group-path')
        'review.meta'                 = @('--repo', '--host')
        'review.mock-provider'        = @('--responder', '--log', '--ttl', '--out')
        'review.parse-args'           = @('--out')
        'review.plan-diff'            = @('--out', '--pr', '--repo', '--host', '--max-chunk-lines', '--effort',
                                          '--deadline')
        'review.pr-context'           = @('--out', '--host')
        'review.presubmit'            = @('--host', '--new-findings')
        'review.publish-assets'       = @('--pr', '--reviewed-repo', '--files', '--findings', '--findings-out',
                                          '--out', '--host', '--skill-args')
        'review.recover-findings'     = @('--plan', '--out')
        'review.repo-context'         = @('--plan', '--worktree', '--out')
        'review.resolve-anchors'      = @('--diff', '--input', '--out')
        'review.revert-hunk'          = @('--diff', '--hunk', '--tree', '--out')
        'review.run'                  = @('--effort', '--fail-on', '--timeout-minutes', '--approval-mode')
        'review.save-artifact'        = @('--findings', '--composed', '--report', '--target', '--effort', '--out',
                                          '--workspace-root')
        'review.scratch-tree'         = @('--worktree', '--label', '--fetched-sha', '--out')
        'review.script-lint'          = @('--plan', '--worktree', '--out')
        'review.submit'               = @('--pr', '--repo', '--review', '--skill-args', '--host')
        'review.test-delta'           = @('--report', '--baseline', '--pr-worktree', '--out', '--timeout')
        'review.test-efficacy'        = @('--worktree', '--base', '--out')
        'review.test-plan'            = @('--plan', '--pr', '--repo', '--worktree', '--build-test', '--out',
                                          '--host')
    }

    # Boolean options declared by a command (take no value): context -> @(flags).
    $script:QwenContextBoolFlags = @{
        'mcp.add'                     = @('--trust')
        'mcp.reconnect'               = @('--all')
        'mcp.approve'                 = @('--all')
        'mcp.reject'                  = @('--all')
        'extensions.install'          = @('--auto-update', '--pre-release', '--consent')
        'extensions.update'           = @('--all')
        'board'                       = @('--json')
        'board.ask'                   = @('--wait')
        'sessions.list'               = @('--json')
        'sessions.ps'                 = @('--json')
        'sessions.controllers.add'    = @('--json')
        'sessions.controllers.list'   = @('--json')
        'batch.run'                   = @('--dry-run')
        'batch.collect'               = @('--wait')
        'batch.clean'                 = @('--force')
        'sandbox'                     = @('--verify')
        'serve'                       = @('--require-auth', '--enable-session-shell', '--experimental-lsp',
                                          '--restore-ask-user-question', '--web', '--open', '--open-with-auth',
                                          '--token-qr', '--local-control', '--agent-host-allow-http',
                                          '--http-bridge', '--allow-private-auth-base-url',
                                          '--experimental-paired-engines', '--experimental-managed-agents',
                                          '--experimental-managed-runtime-worker',
                                          '--experimental-managed-runtime-auto-local', '--rate-limit')
        'review.ab-drive'             = @('--shared-once')
        'review.agent-prompt'         = @('--all-chunks', '--roster', '--batch', '--whole-diff')
        'review.base-tree'            = @('--install')
        'review.build-test'           = @('--install', '--build-only', '--resume')
        'review.capture-local'        = @('--untracked')
        'review.fetch-pr'             = @('--resume')
        'review.findings'             = @('--print')
        'review.fix-delta'            = @('--snapshot')
        'review.parse-args'           = @('--stdin')
        'review.publish-assets'       = @('--user-authorized')
        'review.revert-hunk'          = @('--list')
        'review.run'                  = @('--comment', '--resume', '--json', '--quiet')
        'review.scratch-tree'         = @('--standalone')
        'review.submit'               = @('--user-authorized', '--dry-run')
    }

    # Context-specific enum values: "context.--flag" -> @(choices).
    $script:QwenContextEnumFlags = @{
        'mcp.add.--scope'                  = @('user', 'project')
        'mcp.add.--transport'              = @('stdio', 'sse', 'http')
        'extensions.install.--scope'       = @('user', 'project', 'workspace')
        'extensions.settings.set.--scope'  = @('user', 'workspace')
        'sandbox.--sandbox'                = @('true', 'false', 'docker', 'podman', 'sandbox-exec')
        'serve.--profile'                  = @('default', 'hosted-harness')
        'serve.--memory-project-scope'     = @('git-root', 'workspace')
        'serve.--memory-pressure-mode'     = @('off', 'observe')
        'serve.--child-heap-mode'          = @('off', 'observe', 'admit', 'enforce')
        'serve.--mcp-budget-mode'          = @('enforce', 'warn', 'off')
        'serve.--external-tool-guard-mode' = @('off', 'required')
        'review.run.--effort'              = @('low', 'medium', 'high')
        'review.run.--fail-on'             = @('none', 'request-changes')
        'review.run.--approval-mode'       = @('plan', 'default', 'auto', 'auto-edit', 'yolo')
        'review.capture-local.--effort'    = @('low', 'medium', 'high')
        'review.fetch-pr.--effort'         = @('low', 'medium', 'high')
        'review.plan-diff.--effort'        = @('low', 'medium', 'high')
        'review.save-artifact.--effort'    = @('medium', 'high')
        'review.comment-body.--kind'       = @('review', 'inline', 'issue')
        'review.agent-prompt.--role'       = @('docs-nav', '0', '1a', '1b', '1c', '1d', '1e', '2', '3a', '3b',
                                               '3c', '4', '5', '6a', '6b', '6c', '6d', '7', 'prose-exec',
                                               'test-matrix', 'invariant-a', 'invariant-b', 'invariant-c',
                                               'verify', 'reverse-audit', 'fix-audit')
    }

    # Subcommand paths (L2) whose first positional argument accepts path completion.
    $script:QwenPathPositionalL2 = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('extensions.link', 'extensions.new', 'extensions.install', 'batch.run',
                    'review.plan-diff', 'review.test-efficacy'),
        [System.StringComparer]::Ordinal
    )

    # Positional enum values for specific subcommand paths.
    $script:QwenPositionalEnums = @{
        'channel.configure-weixin' = @('clear')
        'channel.set'              = @('all')
    }

    # Placeholder values for positional slots that are free-form and should not
    # fall back to noisy filesystem completion.
    $script:QwenPositionalPlaceholders = @{
        'mcp.add'                     = @('<name>', '<commandOrUrl>', '<arg>')
        'mcp.remove'                  = @('<name>')
        'mcp.reconnect'               = @('<server-name>')
        'mcp.approve'                 = @('<name>')
        'mcp.reject'                  = @('<name>')
        'extensions.install'          = @('<source>')
        'extensions.uninstall'        = @('<name>')
        'extensions.update'           = @('<name>')
        'extensions.disable'          = @('<name>')
        'extensions.enable'           = @('<name>')
        'extensions.new'              = @('<path>', '<template>')
        'extensions.settings.set'     = @('<name>', '<setting>')
        'extensions.settings.list'    = @('<name>')
        'extensions.sources.add'      = @('<source>')
        'extensions.sources.remove'   = @('<name>')
        'extensions.sources.update'   = @('<name>')
        'channel.start'               = @('<name>')
        'channel.set'                 = @('<name>')
        'channel.pairing.list'        = @('<name>')
        'channel.pairing.approve'     = @('<name>', '<code>')
        'board.task'                  = @('<subject>')
        'board.claim'                 = @('<id>')
        'board.done'                  = @('<id>')
        'board.ask'                   = @('<to>', '<question>')
        'board.answer'                = @('<id>', '<answer>')
        'board.decline'               = @('<id>', '<reason>')
        'sessions.controllers.remove' = @('<id>')
        'batch.collect'               = @('<task-id>')
        'batch.retry'                 = @('<task-id>')
        'batch.cancel'                = @('<task-id>')
        'batch.clean'                 = @('<task-id>')
        'sandbox'                     = @('<cmd>')
        'review.run'                  = @('<target>')
        'review.parse-args'           = @('<raw>')
        'review.meta'                 = @('<pr_number>')
        'review.issue-context'        = @('<pr_number>')
        'review.fetch-diff'           = @('<pr_number>')
        'review.comment-body'         = @('<id>')
        'review.fetch-pr'             = @('<pr_number>', '<owner_repo>')
        'review.pr-context'           = @('<pr_number>', '<owner_repo>')
        'review.comment-status'       = @('<pr_number>', '<owner_repo>')
        'review.load-rules'           = @('<base_ref>')
        'review.presubmit'            = @('<pr_number>', '<commit_sha>', '<owner_repo>', '<out_path>')
        'review.cleanup'              = @('<target>')
    }

    # ---- Short alias maps (ordinal: '-H' and '-h' are different flags) --------------------------

    $script:QwenShortAliases = ConvertTo-QwenOrdinalMap @{
        '-d' = '--debug'
        '-m' = '--model'
        '-p' = '--prompt'
        '-i' = '--prompt-interactive'
        '-s' = '--sandbox'
        '-y' = '--yolo'
        '-e' = '--extensions'
        '-l' = '--list-extensions'
        '-o' = '--output-format'
        '-c' = '--continue'
        '-r' = '--resume'
        '-v' = '--version'
        '-h' = '--help'
    }

    # --sandbox (-s) is declared by the default command ('$0') builder and by 'sandbox'
    # only: inside 'mcp', 'extensions', ... neither form means --sandbox.
    $script:QwenRootOnlyFlags = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('--sandbox'), [System.StringComparer]::Ordinal
    )

    $script:QwenContextShortAliases = @{
        'mcp.add'       = ConvertTo-QwenOrdinalMap @{
            '-s' = '--scope'
            '-t' = '--transport'
            '-e' = '--env'
            '-H' = '--header'
        }
        'mcp.reconnect' = ConvertTo-QwenOrdinalMap @{
            '-a' = '--all'
        }
        'sandbox'       = ConvertTo-QwenOrdinalMap @{
            '-s' = '--sandbox'
        }
    }

    # Reverse map (long -> short) built once at load time.
    $script:QwenAliasReverse = @{}
    $script:QwenShortAliases.GetEnumerator() |
        ForEach-Object { $script:QwenAliasReverse[$_.Value] = $_.Key }

    $script:QwenContextAliasReverse = @{}
    foreach ($entry in $script:QwenContextShortAliases.GetEnumerator()) {
        $reverse = @{}
        foreach ($alias in $entry.Value.GetEnumerator()) {
            $reverse[$alias.Value] = $alias.Key
        }
        $script:QwenContextAliasReverse[$entry.Key] = $reverse
    }

    # ---- Descriptions --------------------------------------------------------------------------

    $script:QwenCmdDesc = @{
        mcp        = 'Manage MCP servers'
        extensions = 'Manage extensions'
        hooks      = 'Manage hooks (use /hooks in interactive mode)'
        hook       = 'Alias for hooks'
        channel    = 'Manage messaging channels (Telegram, Discord, etc.)'
        board      = 'Share work with other agents through a board'
        serve      = 'Run Qwen Code as a local HTTP daemon'
        sessions   = 'Manage Qwen Code sessions'
        batch      = 'Run many independent requests through the DashScope Batch API'
        update     = 'Check for Qwen Code updates and install if available'
        sandbox    = 'Inspect tool confinement, verify it, or run one confined command'
        review     = 'Run a review non-interactively (run), plus the /review skill helpers'
    }

    $script:QwenSubcmdDesc = @{
        'mcp.add'                        = 'Add an MCP server'
        'mcp.remove'                     = 'Remove an MCP server'
        'mcp.list'                       = 'List configured MCP servers'
        'mcp.reconnect'                  = 'Reconnect MCP server(s)'
        'mcp.approve'                    = 'Approve a gated MCP server (.mcp.json or workspace settings)'
        'mcp.reject'                     = 'Reject a gated MCP server (.mcp.json or workspace settings)'
        'extensions.install'             = 'Install an extension (URL, local path, or npm package)'
        'extensions.uninstall'           = 'Uninstall an extension'
        'extensions.list'                = 'List installed extensions'
        'extensions.update'              = 'Update extensions'
        'extensions.disable'             = 'Disable an extension'
        'extensions.enable'              = 'Enable an extension'
        'extensions.link'                = 'Link a local development extension (live)'
        'extensions.new'                 = 'Scaffold a new extension from boilerplate'
        'extensions.settings'            = 'Manage extension settings'
        'extensions.sources'             = 'Manage marketplace sources for discovering extensions'
        'extensions.settings.set'        = 'Set a specific extension setting'
        'extensions.settings.list'       = 'List all settings for an extension'
        'extensions.sources.add'         = 'Add a marketplace source (Claude format)'
        'extensions.sources.remove'      = 'Remove a marketplace source'
        'extensions.sources.list'        = 'List configured marketplace sources'
        'extensions.sources.update'      = 'Re-fetch a marketplace source and its plugin listing'
        'channel.start'                  = 'Start channels (all or named)'
        'channel.stop'                   = 'Stop the channel service'
        'channel.status'                 = 'Show channel service status'
        'channel.reload'                 = 'Reload the daemon-managed channel worker (re-reads settings.json)'
        'channel.set'                    = 'Set the channel selection for a running qwen serve daemon'
        'channel.pairing'                = 'Manage DM pairing requests'
        'channel.configure-weixin'       = 'Configure WeChat channel (login or "clear")'
        'channel.pairing.list'           = 'List pending pairing requests for a channel'
        'channel.pairing.approve'        = 'Approve a pending pairing request'
        'board.show'                     = 'Print the board once'
        'board.task'                     = 'Create a task'
        'board.claim'                    = 'Take ownership of a task'
        'board.done'                     = 'Complete a task you own'
        'board.ask'                      = 'Ask another actor a question'
        'board.answer'                   = 'Answer an ask addressed to you'
        'board.decline'                  = 'Decline an ask addressed to you'
        'board.prune'                    = 'Remove settled items older than a cutoff'
        'sessions.list'                  = 'List sessions'
        'sessions.ps'                    = 'List registered and managed Qwen Code sessions'
        'sessions.controllers'           = 'Manage the controller tokens that may drive your sessions'
        'sessions.controllers.add'       = 'Mint a controller token and print it once'
        'sessions.controllers.list'      = 'List the controllers this Qwen home trusts'
        'sessions.controllers.remove'    = 'Revoke a controller by id'
        'batch.run'                      = 'Run an agent-prepared batch plan: assemble, submit, record the task'
        'batch.collect'                  = 'Collect a workflow task: reconcile, download, validate, deliver'
        'batch.retry'                    = 'Resubmit only the failed items of a workflow task'
        'batch.cancel'                   = "Cancel a workflow task's active batch"
        'batch.list'                     = 'List all recorded workflow tasks with their project'
        'batch.check'                    = 'Verify credentials and the Batch route (no billed request)'
        'batch.clean'                    = "Delete a workflow task's local record"
        'review.run'                     = 'Run a full /review non-interactively and print the verdict'
        'review.parse-args'              = 'Parse the /review skill argument string'
        'review.match-remote'            = 'Print the git remote whose URL matches an owner/repo'
        'review.meta'                    = 'Print the review platform identity facts for this repository'
        'review.issue-context'           = "Fetch a PR's closing issues and render them as context"
        'review.fetch-diff'              = "Write a PR's full unified diff to a file"
        'review.comment-body'            = 'Print one comment body'
        'review.fetch-pr'                = 'Prepare a PR review worktree and write a review plan'
        'review.capture-local'           = 'Capture local changes as one diff and partition it into chunks'
        'review.capture-tui'             = 'Run a command in a private tmux server and capture what it rendered'
        'review.plan-diff'               = 'Partition a captured diff file into review chunks (JSON plan)'
        'review.cache-commit'            = "Promote a capture's cache candidate into .qwen/review-cache/"
        'review.repo-context'            = 'Attach bounded repository-specific context to a review plan'
        'review.pr-context'              = 'Fetch PR metadata and comments as a Markdown context file'
        'review.comment-status'          = "Emit a per-thread status index for a PR's inline comments"
        'review.load-rules'              = 'Read project review rules from the base branch'
        'review.agent-prompt'            = "Build a review agent's launch prompt from the plan"
        'review.emit-workflow'           = 'Emit a review roster or batch as a runnable workflow script'
        'review.build-test'              = 'Build and test the workspaces the diff changes'
        'review.base-tree'               = "Build the PR's merge base in a sibling worktree"
        'review.scratch-tree'            = 'Create a throwaway worktree at the commit under review'
        'review.test-delta'              = "Rerun the PR side's failed tests on the base tree"
        'review.fix-delta'               = 'Snapshot the tree before --fix, then diff it afterwards'
        'review.drive'                   = 'Start something, wait until it is up, drive it, capture it'
        'review.ab-drive'                = 'Drive the same script against the PR and base trees'
        'review.mock-provider'           = 'Serve mock OpenAI and Anthropic endpoints for the review'
        'review.extract-step'            = "Extract one workflow step's run: script into an executable"
        'review.script-lint'             = 'Run shellcheck/actionlint/hadolint over changed scripts'
        'review.dedup-candidates'        = 'Drop pooled candidates the carried ledger already holds'
        'review.revert-hunk'             = 'List the diff hunks, or apply one in reverse in a tree'
        'review.resolve-anchors'         = "Compute each finding's diff line from its quoted snippet"
        'review.check-coverage'          = "Prove the diff was read, from the harness's transcripts"
        'review.cost-ledger'             = "Aggregate this review's model-call cost"
        'review.presubmit'               = 'Pre-submission checks for /review Step 7'
        'review.test-efficacy'           = "Check whether the diff's new tests gate its new behaviour"
        'review.test-plan'               = "Rule on the PR Test Plan's checkable claims"
        'review.findings'                = "Validate and canonicalize the review's findings"
        'review.recover-findings'        = 'Recover the certified agent results of an interrupted review'
        'review.publish-assets'          = 'Publish review evidence images to the assets repository'
        'review.compose-review'          = 'Compute the review event and body from the drafted comments'
        'review.save-artifact'           = 'Create a durable versioned code-review JSON document'
        'review.submit'                  = 'Post the review to the pull request'
        'review.cleanup'                 = 'Post-review cleanup: remove worktree, branch ref, temp files'
    }

    # Global flag descriptions (by flag name).
    $script:QwenFlagDesc = @{
        '--telemetry'                = '[boolean] Enable telemetry (deprecated: use settings.json)'
        '--telemetry-target'         = '[string]  Telemetry target: local|gcp (deprecated)'
        '--telemetry-otlp-endpoint'  = '[string]  OTLP collector endpoint URL (deprecated)'
        '--telemetry-otlp-protocol'  = '[string]  OTLP protocol: grpc|http (deprecated)'
        '--telemetry-log-prompts'    = '[boolean] Log prompts for telemetry (deprecated)'
        '--telemetry-outfile'        = '[path]    Write telemetry to file (deprecated)'
        '--debug'                    = '[boolean] Run in debug mode'
        '--bare'                     = '[boolean] Minimal mode: skip startup auto-discovery'
        '--safe-mode'                = '[boolean] Disable all customizations for troubleshooting'
        '--insecure'                 = '[boolean] Skip TLS certificate verification for API connections'
        '--proxy'                    = '[string]  HTTP proxy URL (deprecated)'
        '--chat-recording'           = '[boolean] Enable chat recording to disk'
        '--model'                    = '[string]  Model to use'
        '--advisor'                  = '[string]  Advisor model selector ("off" disables)'
        '--fallback-model'           = '[array]   Fallback model(s) for capacity errors (max 3)'
        '--prompt'                   = '[string]  Prompt text (deprecated; use positional)'
        '--prompt-interactive'       = '[string]  Prompt and continue in interactive mode'
        '--system-prompt'            = '[string]  Override session system prompt'
        '--append-system-prompt'     = '[string]  Append to session system prompt'
        '--output-style'             = '[string]  Output style for this run (e.g. Concise, Explanatory)'
        '--sandbox'                  = '[string]  Run in a sandbox: true|false|docker|podman|sandbox-exec'
        '--sandbox-image'            = '[string]  Sandbox container image URI (deprecated)'
        '--yolo'                     = '[boolean] Auto-accept all actions (YOLO mode)'
        '--approval-mode'            = '[string]  Tool approval mode: plan|default|auto|auto-edit|yolo'
        '--acp'                      = '[boolean] Start in ACP mode'
        '--experimental-lsp'         = '[boolean] Enable experimental LSP support'
        '--restore-ask-user-question' = '[boolean] Re-hang an unanswered ask_user_question on daemon resume'
        '--channel'                  = '[string]  Channel identifier: VSCode|ACP|SDK|CI|desktop|daemon'
        '--allowed-mcp-server-names' = '[array]   Allowed MCP server names'
        '--mcp-config'               = '[path]    MCP server config: JSON file path or inline JSON'
        '--allowed-tools'            = '[array]   Tools to allow (bypass confirmation)'
        '--extensions'               = '[array]   Extensions to use (-e)'
        '--list-extensions'          = '[boolean] List available extensions and exit'
        '--include-directories'      = '[array]   Additional workspace directories (--add-dir)'
        '--add-dir'                  = '[array]   Additional workspace directories (--include-directories)'
        '--openai-logging'           = '[boolean] Enable OpenAI API call logging'
        '--openai-logging-dir'       = '[path]    Directory for OpenAI API logs'
        '--openai-api-key'           = '[string]  OpenAI API key'
        '--openai-base-url'          = '[string]  OpenAI base URL override'
        '--screen-reader'            = '[boolean] Enable screen reader accessibility mode'
        '--input-format'             = '[string]  Input format: text|stream-json'
        '--output-format'            = '[string]  Output format: text|json|stream-json'
        '--include-partial-messages' = '[boolean] Include partial assistant messages (stream-json)'
        '--json-fd'                  = '[number]  File descriptor for structured JSON event output'
        '--json-file'                = '[path]    File for structured JSON event output'
        '--json-schema'              = '[string]  JSON Schema for the final output (JSON or @path)'
        '--input-file'               = '[path]    File for receiving remote input commands (JSONL)'
        '--continue'                 = '[boolean] Resume the most recent session'
        '--resume'                   = '[string]  Resume a specific session by ID'
        '--session-id'               = '[string]  Specify session ID for this run'
        '--fork-session'             = '[boolean] Fork a new session from the resumed one'
        '--worktree'                 = '[string]  Start the session inside a git worktree (slug or PR)'
        '--max-session-turns'        = '[number]  Maximum session turns'
        '--max-wall-time'            = '[string]  Run-level wall-clock budget (e.g. 90, 30s, 5m, 1h)'
        '--max-tool-calls'           = '[number]  Maximum cumulative tool calls for the run'
        '--max-subagent-depth'       = '[number]  Maximum sub-agent nesting depth'
        '--core-tools'               = '[array]   Core tool paths'
        '--exclude-tools'            = '[array]   Tools to exclude'
        '--disabled-slash-commands'  = '[array]   Slash command names to hide/disable'
        '--auth-type'                = '[string]  Authentication type'
        '--help'                     = '[boolean] Show help'
        '--version'                  = '[boolean] Show version'
    }

    # Context flag descriptions: "context.--flag" -> text, found through the same
    # deepest-first walk as the flags ('mcp.--all' covers every mcp subcommand).  A
    # context flag without an entry is described by its kind ([boolean], choices, [value]).
    $script:QwenContextFlagDesc = @{
        'mcp.--scope'                     = '[string]  Configuration scope: user|project'
        'mcp.--transport'                 = '[string]  MCP transport: stdio|sse|http'
        'mcp.--env'                       = '[array]   Environment variable: KEY=value'
        'mcp.--header'                    = '[array]   HTTP header: "Name: value"'
        'mcp.--timeout'                   = '[number]  Connection timeout in milliseconds'
        'mcp.--trust'                     = '[boolean] Trust server (bypass all tool confirmations)'
        'mcp.--description'               = '[string]  Server description'
        'mcp.--include-tools'             = '[array]   Tools to include (comma-separated)'
        'mcp.--exclude-tools'             = '[array]   Tools to exclude (comma-separated)'
        'mcp.--oauth-client-id'           = '[string]  OAuth client ID for MCP server authentication'
        'mcp.--oauth-client-secret'       = '[string]  OAuth client secret for MCP server authentication'
        'mcp.--oauth-redirect-uri'        = '[string]  OAuth redirect URI'
        'mcp.--oauth-authorization-url'   = '[string]  OAuth authorization URL'
        'mcp.--oauth-token-url'           = '[string]  OAuth token URL'
        'mcp.--oauth-scopes'              = '[array]   OAuth scopes (comma-separated)'
        'mcp.--all'                       = '[boolean] Apply to all servers'
        'extensions.--scope'              = '[string]  Configuration scope'
        'extensions.--ref'                = '[string]  Git ref to install from'
        'extensions.--auto-update'        = '[boolean] Enable auto-update for this extension'
        'extensions.--pre-release'        = '[boolean] Include pre-release versions'
        'extensions.--registry'           = '[string]  Custom npm registry URL'
        'extensions.--consent'            = '[boolean] Acknowledge risks and skip confirmation'
        'extensions.--all'                = '[boolean] Update all extensions'
        'channel.--daemon-url'            = '[string]  Daemon base URL (default: $QWEN_DAEMON_URL)'
        'channel.--token'                 = '[string]  Bearer token (default: $QWEN_SERVER_TOKEN)'
        'channel.--timeout'               = '[number]  Request timeout in milliseconds'
        'channel.--channel'               = '[array]   Internal daemon-managed channel selection'
        'board.--board'                   = '[string]  Board name'
        'board.--as'                      = '[string]  Declared actor name'
        'board.--json'                    = '[boolean] Emit JSON'
        'board.--owner'                   = '[string]  Task owner'
        'board.--note'                    = '[string]  Completion note'
        'board.--about'                   = '[string]  What the question is about'
        'board.--wait'                    = '[boolean] Wait for the answer'
        'board.--timeout'                 = '[number]  Seconds to wait for the answer (default 30)'
        'board.--ttl'                     = '[number]  Seconds the ask stays open (default 900)'
        'board.--older-than'              = '[number]  Cutoff in days (default 7)'
        'sessions.--json'                 = '[boolean] Output as JSON'
        'sessions.--limit'                = '[number]  Maximum number of sessions to show (default 20)'
        'sessions.--label'                = '[string]  What to call this controller, for later revocation'
        'batch.--dry-run'                 = '[boolean] Assemble and show items without uploading'
        'batch.--expect'                  = '[string]  Submit only if the batch matches this --dry-run digest'
        'batch.--wait'                    = '[boolean] Poll until the batch settles, then collect'
        'batch.--timeout'                 = '[number]  Seconds to wait with --wait before giving up'
        'batch.--max-output-tokens'       = '[number]  Output limit for the new attempt'
        'batch.--force'                   = '[boolean] Delete even if a batch may still be running'
        'sandbox.--verify'                = '[boolean] Verify the kernel boundary'
        'sandbox.--sandbox'               = '[string]  Sandbox to inspect: true|false|docker|podman|sandbox-exec'
        'serve.--port'                    = '[number]  TCP port to bind (default 4170; 0 = ephemeral)'
        'serve.--hostname'                = '[string]  Interface to bind (non-loopback requires a token)'
        'serve.--token'                   = '[string]  Bearer token required on every request'
        'serve.--workspace'               = '[array]   Absolute workspace path to register (repeatable)'
        'serve.--channel'                 = '[array]   Start a daemon-managed channel worker (or "all")'
        'serve.--experimental-lsp'        = '[boolean] Forward the experimental LSP opt-in to sessions'
        'serve.--restore-ask-user-question' = '[boolean] Re-hang an unanswered ask_user_question on resume'
        'serve.--web'                     = '[boolean] Serve the Web Shell UI (default true; --no-web)'
        'serve.--open'                    = '[boolean] Open the Web Shell in a browser once listening'
        'serve.--require-auth'            = '[boolean] Refuse to start without a bearer token'
        'review.--resume'                 = '[boolean] Continue an interrupted review'
        'review.--worktree'               = '[string]  Review worktree path'
        'review.--timeout'                = '[number]  Timeout'
        'review.--effort'                 = '[string]  Review effort: low|medium|high'
        'review.run.--comment'            = '[boolean] Authorise posting the review to GitHub (PR targets)'
        'review.run.--json'               = '[boolean] Print the full result as JSON on stdout'
        'review.run.--fail-on'            = '[string]  Exit 3 on this outcome: none|request-changes'
        'review.run.--timeout-minutes'    = '[number]  Terminate the review after this long (default 120)'
        'review.run.--approval-mode'      = '[string]  Approval mode for the child CLI (default yolo)'
        'review.run.--quiet'              = '[boolean] Suppress the child CLI progress stream on stderr'
    }
}

#region -- Helpers ------------------------------------------------------------------------------

function ConvertTo-QwenOrdinalMap {
    param([hashtable]$Map)
    $ordinal = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $Map.GetEnumerator()) { $ordinal[$entry.Key] = $entry.Value }
    Write-Output -InputObject $ordinal -NoEnumerate
}

function New-QwenCompletion {
    param(
        [Parameter(Mandatory)]
        [string]$CompletionText,

        [string]$ListItemText  = '',
        [string]$Tooltip       = '',

        [System.Management.Automation.CompletionResultType]
        $ResultType = [System.Management.Automation.CompletionResultType]::ParameterValue
    )
    if ([string]::IsNullOrEmpty($ListItemText)) { $ListItemText = $CompletionText }
    if ([string]::IsNullOrEmpty($Tooltip))      { $Tooltip      = $ListItemText  }
    [System.Management.Automation.CompletionResult]::new(
        $CompletionText, $ListItemText, $ResultType, $Tooltip
    )
}

# Context keys for the current command path, deepest first ('board.ask', 'board');
# empty at the root.
function Get-QwenContextChain {
    param([string]$Sub, [string]$SubSub, [string]$SubSubSub)
    if (-not $Sub) { return }
    if ($SubSub) {
        if ($SubSubSub) { "$Sub.$SubSub.$SubSubSub" }
        "$Sub.$SubSub"
    }
    $Sub
}

# Returns 'bool' or 'value' when a context declares the flag, else $null.
function Get-QwenContextFlagKind {
    param([string]$FlagName, [string[]]$ContextKeys)
    foreach ($key in $ContextKeys) {
        if ($script:QwenContextBoolFlags[$key] -ccontains $FlagName) { return 'bool' }
        if ($script:QwenContextFlags[$key] -ccontains $FlagName) { return 'value' }
    }
    return $null
}

function Resolve-QwenFlagName {
    param([string]$FlagName, [string[]]$ContextKeys)
    foreach ($key in $ContextKeys) {
        $ctxMap = $script:QwenContextShortAliases[$key]
        if ($ctxMap -and $ctxMap.ContainsKey($FlagName)) {
            return $ctxMap[$FlagName]
        }
    }
    $long = $script:QwenShortAliases[$FlagName]
    if (-not $long -or ($ContextKeys.Count -gt 0 -and $script:QwenRootOnlyFlags.Contains($long))) {
        return $FlagName
    }
    $long
}

function Get-QwenShortAlias {
    param([string]$FlagName, [string[]]$ContextKeys)
    foreach ($key in $ContextKeys) {
        $ctxReverse = $script:QwenContextAliasReverse[$key]
        if ($ctxReverse -and $ctxReverse.ContainsKey($FlagName)) {
            return $ctxReverse[$FlagName]
        }
    }
    return $script:QwenAliasReverse[$FlagName]
}

# Returns $true when the flag consumes the next token as its value.
function Test-QwenFlagTakesValue {
    param([string]$FlagName, [string[]]$ContextKeys)
    $r = Resolve-QwenFlagName -FlagName $FlagName -ContextKeys $ContextKeys

    # A command's own declaration wins over a global flag of the same name.
    $kind = Get-QwenContextFlagKind -FlagName $r -ContextKeys $ContextKeys
    if ($kind) { return $kind -eq 'value' }

    if ($ContextKeys.Count -gt 0 -and $script:QwenRootOnlyFlags.Contains($r)) { return $false }

    # Global value-taking flag categories.
    if ($null -ne $script:QwenEnumFlags[$r]) { return $true }
    if ($script:QwenStringFlags -contains $r) { return $true }
    if ($script:QwenNumberFlags -contains $r) { return $true }
    if ($script:QwenArrayFlags  -contains $r) { return $true }
    if ($script:QwenPathFlags   -contains $r) { return $true }
    if ($script:QwenDirFlags    -contains $r) { return $true }

    # Global boolean flags and unknown flags take no value.
    return $false
}

# Returns the known enum choices for a flag in the given context, or $null.
function Get-QwenEnumValues {
    param([string]$FlagName, [string[]]$ContextKeys)
    $r = Resolve-QwenFlagName -FlagName $FlagName -ContextKeys $ContextKeys

    foreach ($key in $ContextKeys) {
        $vals = $script:QwenContextEnumFlags["$key.$r"]
        if ($vals) { return $vals }
        # Declared here without choices: a global enum of the same name does not apply.
        if (Get-QwenContextFlagKind -FlagName $r -ContextKeys $key) { return $null }
    }

    if ($ContextKeys.Count -gt 0 -and $script:QwenRootOnlyFlags.Contains($r)) { return $null }
    return $script:QwenEnumFlags[$r]
}

function Get-QwenFlagDescription {
    param([string]$FlagName, [string[]]$ContextKeys)
    $kind = Get-QwenContextFlagKind -FlagName $FlagName -ContextKeys $ContextKeys
    if (-not $kind) { return $script:QwenFlagDesc[$FlagName] ?? '' }

    foreach ($key in $ContextKeys) {
        $desc = $script:QwenContextFlagDesc["$key.$FlagName"]
        if ($desc) { return $desc }
    }
    if ($kind -eq 'bool') { return '[boolean]' }
    $choices = Get-QwenEnumValues -FlagName $FlagName -ContextKeys $ContextKeys
    if ($choices) { return '[string]  ' + ($choices -join '|') }
    return '[value]'
}

# Builds the full flag set for the current command context.
function Get-QwenFlagSet {
    param([string[]]$ContextKeys)

    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $script:QwenEnumFlags.Keys  | ForEach-Object { $null = $set.Add($_) }
    $script:QwenBoolFlags        | ForEach-Object { $null = $set.Add($_) }
    $script:QwenStringFlags      | ForEach-Object { $null = $set.Add($_) }
    $script:QwenNumberFlags      | ForEach-Object { $null = $set.Add($_) }
    $script:QwenArrayFlags       | ForEach-Object { $null = $set.Add($_) }
    $script:QwenPathFlags        | ForEach-Object { $null = $set.Add($_) }
    $script:QwenDirFlags         | ForEach-Object { $null = $set.Add($_) }
    if ($ContextKeys.Count -gt 0) { $set.ExceptWith($script:QwenRootOnlyFlags) }

    foreach ($key in $ContextKeys) {
        foreach ($table in @($script:QwenContextFlags, $script:QwenContextBoolFlags)) {
            $ctxFlags = $table[$key]
            if ($ctxFlags) { $ctxFlags | ForEach-Object { $null = $set.Add($_) } }
        }
    }
    return $set
}

function Get-QwenPositionalPlaceholder {
    param(
        [string]$ContextKey,
        [int]$PositionIndex
    )
    $placeholders = $script:QwenPositionalPlaceholders[$ContextKey]
    if (-not $placeholders) { return $null }
    if ($PositionIndex -lt $placeholders.Count) {
        return $placeholders[$PositionIndex]
    }
    return $placeholders[-1]
}

function Write-QwenLongFlagResults {
    param(
        [string]$WordToComplete,
        [string[]]$ContextKeys
    )
    $flagSet = Get-QwenFlagSet -ContextKeys $ContextKeys
    foreach ($flag in $flagSet) {
        if ($flag -notlike "$WordToComplete*") { continue }
        $desc  = Get-QwenFlagDescription -FlagName $flag -ContextKeys $ContextKeys
        $short = Get-QwenShortAlias -FlagName $flag -ContextKeys $ContextKeys
        $tip = if ($short) { "$flag (alias: $short): $desc" } else { "${flag}: $desc" }
        New-QwenCompletion $flag -ResultType ParameterName -Tooltip $tip
    }
}

#endregion

#region -- Completer scriptblock ----------------------------------------------------------------

function Complete-QwenNative {
    param(
        [string]$WordToComplete,
        $CommandAst,
        [int]$CursorPosition
    )

    Initialize-QwenCompleterData

    if ($null -eq $CommandAst) { return }

    $allElements = @($CommandAst.CommandElements)
    if ($allElements.Count -eq 0) { return }

    # -------------------------------------------------------------------------
    # The word under the cursor is the engine's $WordToComplete (empty in an
    # empty slot). Committed arguments are the elements that end before the
    # cursor; extents and the cursor are both absolute offsets in the input,
    # so this holds when the command follows another statement. A string
    # constant contributes its unquoted value, as the shell passes "mcp" to
    # qwen as mcp; every other element (--flag parameters included) keeps its
    # Extent.Text, which is safe under StrictMode.
    # -------------------------------------------------------------------------
    $committedArgs = @(foreach ($el in ($allElements | Select-Object -Skip 1)) {
        if ($el.Extent.EndOffset -lt $CursorPosition) {
            if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $el.Value } else { $el.Extent.Text }
        }
    })

    # -------------------------------------------------------------------------
    # State machine: walk committed args to determine context.
    # Tracks up to 3 command levels plus expectingValue / currentFlag.
    # -------------------------------------------------------------------------
    $sub    = $null   # e.g. 'mcp'
    $subsub = $null   # e.g. 'add'
    $sub3   = $null   # e.g. 'set'  (extensions settings set / sessions controllers add)
    $ctxKeys = [string[]]@()
    $expectingValue  = $false
    $currentFlag     = $null
    $positionalCount = 0     # non-flag positionals seen after the deepest command

    foreach ($token in $committedArgs) {
        # yargs stops parsing at '--': everything after it is passed through.
        if ($token -ceq '--') { return }

        if ($expectingValue) {
            $expectingValue = $false
            $currentFlag    = $null
            # yargs never takes a dash-led word other than a negative number as
            # a value, so in '--sandbox -p' the -p is a flag of its own.
            if ($token -notlike '-*' -or $token -match '^-\d') { continue }
        }

        if ($token -like '-*') {
            if ($token -like '*=*') { continue }    # inline --flag=value; value already consumed
            if (Test-QwenFlagTakesValue -FlagName $token -ContextKeys $ctxKeys) {
                $expectingValue = $true
                $currentFlag    = Resolve-QwenFlagName -FlagName $token -ContextKeys $ctxKeys
            }
            continue
        }

        # Positional token. A command name only counts before the current
        # level's first positional: in 'qwen fix mcp' the 'mcp' is prompt text.
        $matched = $false
        if ($positionalCount -eq 0) {
            if ($null -eq $sub) {
                if ($script:QwenTopCommands -ccontains $token) {
                    $sub     = $token
                    $matched = $true
                }
            } elseif ($null -eq $subsub) {
                if ($script:QwenSubSubcommands[$sub] -ccontains $token) {
                    $subsub  = $token
                    $matched = $true
                }
            } elseif ($null -eq $sub3) {
                if ($script:QwenL3Subcommands["$sub.$subsub"] -ccontains $token) {
                    $sub3    = $token
                    $matched = $true
                }
            }
        }

        if ($matched) {
            $ctxKeys = [string[]]@(Get-QwenContextChain -Sub $sub -SubSub $subsub -SubSubSub $sub3)
        } else {
            $positionalCount++
        }
    }

    $isWordPrefix = { param($candidate) $candidate -like ([System.Management.Automation.WildcardPattern]::Escape($WordToComplete) + '*') }

    # =========================================================================
    # 1.  Inline --flag=value completion
    # =========================================================================
    if ($WordToComplete -like '*=*') {
        $eqIdx    = $WordToComplete.IndexOf('=')
        $flagPart = $WordToComplete.Substring(0, $eqIdx)
        $valPfx   = $WordToComplete.Substring($eqIdx + 1)
        $resolved = Resolve-QwenFlagName -FlagName $flagPart -ContextKeys $ctxKeys

        $enumVals = Get-QwenEnumValues -FlagName $resolved -ContextKeys $ctxKeys
        if ($enumVals) {
            $tip = Get-QwenFlagDescription -FlagName $resolved -ContextKeys $ctxKeys
            $enumVals | Where-Object { $_ -like ([System.Management.Automation.WildcardPattern]::Escape($valPfx) + '*') } | ForEach-Object {
                New-QwenCompletion "$flagPart=$_" -ListItemText $_ -Tooltip $tip
            }
            return
        }

        # Path / dir flags with inline syntax (global flags only).
        if (-not (Get-QwenContextFlagKind -FlagName $resolved -ContextKeys $ctxKeys) -and
            ($script:QwenPathFlags -contains $resolved -or $script:QwenDirFlags -contains $resolved)) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($valPfx) |
                ForEach-Object {
                    New-QwenCompletion "$flagPart=$($_.CompletionText)" `
                        -ListItemText $_.ListItemText `
                        -ResultType   $_.ResultType `
                        -Tooltip      $_.ToolTip
                }
        }
        return
    }

    # =========================================================================
    # 2.  Value completion after space-separated value-taking flag
    # =========================================================================
    if ($expectingValue -and ($WordToComplete -notlike '-*' -or $WordToComplete -match '^-\d')) {
        $enumVals = Get-QwenEnumValues -FlagName $currentFlag -ContextKeys $ctxKeys
        if ($enumVals) {
            $tip = Get-QwenFlagDescription -FlagName $currentFlag -ContextKeys $ctxKeys
            $enumVals | Where-Object { & $isWordPrefix $_ } | ForEach-Object {
                New-QwenCompletion $_ -Tooltip $tip
            }
            return
        }

        $isGlobal = -not (Get-QwenContextFlagKind -FlagName $currentFlag -ContextKeys $ctxKeys)

        # Path / dir completion.
        if ($isGlobal -and ($script:QwenPathFlags -contains $currentFlag -or
                            $script:QwenDirFlags  -contains $currentFlag)) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
            return
        }

        # Number placeholder — suppresses filesystem fallback.
        if ($isGlobal -and $script:QwenNumberFlags -contains $currentFlag) {
            if (& $isWordPrefix '') {
                New-QwenCompletion '<n>' -Tooltip "Numeric value for $currentFlag"
            }
            return
        }

        # Generic placeholder — suppresses filesystem fallback for string/array flags.
        if (& $isWordPrefix '') {
            New-QwenCompletion '<value>' -Tooltip "Value for $currentFlag"
        }
        return
    }

    # =========================================================================
    # 3.  Flag completion (word starts with - or --)
    # =========================================================================
    if ($WordToComplete -like '-*') {
        $flagSet = Get-QwenFlagSet -ContextKeys $ctxKeys
        $isShort = $WordToComplete -notlike '--*'

        foreach ($flag in $flagSet) {
            $short = Get-QwenShortAlias -FlagName $flag -ContextKeys $ctxKeys

            if ($isShort) {
                if (-not $short) { continue }
                if ($short -notlike "$WordToComplete*") { continue }
                $desc = Get-QwenFlagDescription -FlagName $flag -ContextKeys $ctxKeys
                New-QwenCompletion $short `
                    -ResultType ParameterName `
                    -Tooltip    "$short -> ${flag}: $desc"
            } else {
                if ($flag -notlike "$WordToComplete*") { continue }
                $desc = Get-QwenFlagDescription -FlagName $flag -ContextKeys $ctxKeys
                $tip = if ($short) { "$flag (alias: $short): $desc" } else { "${flag}: $desc" }
                New-QwenCompletion $flag -ResultType ParameterName -Tooltip $tip
            }
        }
        return
    }

    # =========================================================================
    # 4.  Subcommand / positional completion
    #     A positional already typed where a subcommand was due (unknown word)
    #     ends completion here, so PowerShell's own fallback applies.
    # =========================================================================

    # --- 4a. Have sub + subsub → offer L3 subcommands (or positional values). ---
    if ($sub -and $subsub -and $null -eq $sub3) {
        $l3k  = "$sub.$subsub"
        $l3cs = $script:QwenL3Subcommands[$l3k]
        if ($l3cs) {
            if ($positionalCount -gt 0) { return }
            $l3cs | Where-Object { & $isWordPrefix $_ } | ForEach-Object {
                $tip = $script:QwenSubcmdDesc["$sub.$subsub.$_"] ?? $_
                New-QwenCompletion $_ -Tooltip $tip
            }
            return
        }

        # No L3 commands → offer positional enum / path if applicable.
        $posVals = $script:QwenPositionalEnums[$l3k]
        if ($posVals) {
            $posVals | Where-Object { & $isWordPrefix $_ } | ForEach-Object {
                New-QwenCompletion $_ -Tooltip "Positional: $_"
            }
        }
        if ($script:QwenPathPositionalL2.Contains($l3k) -and $positionalCount -eq 0) {
            [System.Management.Automation.CompletionCompleters]::CompleteFilename($WordToComplete)
        }

        $placeholder = Get-QwenPositionalPlaceholder -ContextKey $l3k -PositionIndex $positionalCount
        if ($placeholder -and (& $isWordPrefix $placeholder)) {
            New-QwenCompletion $placeholder -Tooltip "Positional value for $l3k"
        }

        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-QwenLongFlagResults -WordToComplete '' -ContextKeys $ctxKeys
        }
        return
    }

    # --- 4b. Have sub + subsub + sub3 → positional enum values only. ---
    if ($sub -and $subsub -and $sub3) {
        $posKey  = "$sub.$subsub.$sub3"
        $posVals = $script:QwenPositionalEnums[$posKey]
        if ($posVals) {
            $posVals | Where-Object { & $isWordPrefix $_ } | ForEach-Object {
                New-QwenCompletion $_ -Tooltip "Positional: $_"
            }
        }
        $placeholder = Get-QwenPositionalPlaceholder -ContextKey $posKey -PositionIndex $positionalCount
        if ($placeholder -and (& $isWordPrefix $placeholder)) {
            New-QwenCompletion $placeholder -Tooltip "Positional value for $posKey"
        }
        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-QwenLongFlagResults -WordToComplete '' -ContextKeys $ctxKeys
        }
        return
    }

    # --- 4c. Have sub only → offer L2 subcommands, or the command's own positional. ---
    if ($sub -and $null -eq $subsub) {
        $subs = $script:QwenSubSubcommands[$sub]
        if ($subs) {
            if ($positionalCount -gt 0) { return }
            $subs | Where-Object { -not $script:QwenHiddenCommands.Contains("$sub.$_") -and (& $isWordPrefix $_) } | ForEach-Object {
                $tip = $script:QwenSubcmdDesc["$sub.$_"] ?? $_
                New-QwenCompletion $_ -Tooltip $tip
            }
            return
        }

        $placeholder = Get-QwenPositionalPlaceholder -ContextKey $sub -PositionIndex $positionalCount
        if ($placeholder -and (& $isWordPrefix $placeholder)) {
            New-QwenCompletion $placeholder -Tooltip "Positional value for $sub"
        }
        if ([string]::IsNullOrEmpty($WordToComplete)) {
            Write-QwenLongFlagResults -WordToComplete '' -ContextKeys $ctxKeys
        }
        return
    }

    # --- 4d. Top level → offer L1 subcommands (not after a prompt word). ---
    if ($positionalCount -gt 0) { return }
    $script:QwenTopCommands | Where-Object { -not $script:QwenHiddenCommands.Contains($_) -and (& $isWordPrefix $_) } | ForEach-Object {
        $tip = $script:QwenCmdDesc[$_] ?? $_
        New-QwenCompletion $_ -Tooltip $tip
    }
}

#endregion

#region -- Registration -------------------------------------------------------------------------

Register-ArgumentCompleter -CommandName @('qwen', 'qwen.cmd', 'qwen.ps1') -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    Complete-QwenNative -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
}

#endregion

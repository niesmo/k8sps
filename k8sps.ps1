#Requires -Version 5.1
<#
.SYNOPSIS
    k8sps - A PowerShell shell for Kubernetes

.DESCRIPTION
    A shell wrapper for PowerShell including aliases and functions for kubectl 
    that makes it easy to navigate between and execute commands on different 
    kubernetes clusters and namespaces.

.NOTES
    PowerShell equivalent of k8sh (https://github.com/Comcast/k8sh)
#>

# Script-level variables for namespace (context is managed by kubectl directly)
$script:KUBECTL_NAMESPACE = $null

#region Colors
$script:Colors = @{
    Red       = 'Red'
    Green     = 'Green'
    Yellow    = 'Yellow'
    Blue      = 'Blue'
    Magenta   = 'Magenta'
    Cyan      = 'Cyan'
    White     = 'White'
    Gray      = 'Gray'
}
#endregion

#region Fuzzy Matching
function Get-FuzzyMatches {
    <#
    .SYNOPSIS
        Get fuzzy matches for tab completion
    .DESCRIPTION
        Returns items that match the input using fuzzy matching.
        Prioritizes: exact match > prefix match > contains > fuzzy match
    #>
    param(
        [string]$WordToComplete,
        [string[]]$Candidates
    )
    
    if ([string]::IsNullOrEmpty($WordToComplete)) {
        return $Candidates
    }
    
    $results = @()
    $pattern = ($WordToComplete.ToCharArray() | ForEach-Object { [regex]::Escape($_) }) -join '.*'
    
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrEmpty($candidate)) { continue }
        
        $score = 0
        $lowerCandidate = $candidate.ToLower()
        $lowerWord = $WordToComplete.ToLower()
        
        if ($lowerCandidate -eq $lowerWord) {
            # Exact match - highest priority
            $score = 100
        }
        elseif ($lowerCandidate.StartsWith($lowerWord)) {
            # Prefix match - high priority
            $score = 80
        }
        elseif ($lowerCandidate.Contains($lowerWord)) {
            # Contains match - medium priority
            $score = 60
        }
        elseif ($lowerCandidate -match $pattern) {
            # Fuzzy match - lower priority
            # Bonus for consecutive character matches
            $score = 40
            # Additional score based on how compact the match is
            $matchLength = ($lowerCandidate | Select-String -Pattern $pattern).Matches[0].Length
            $score += [math]::Max(0, 20 - ($matchLength - $WordToComplete.Length))
        }
        
        if ($score -gt 0) {
            $results += [PSCustomObject]@{
                Value = $candidate
                Score = $score
            }
        }
    }
    
    return $results | Sort-Object -Property Score -Descending | Select-Object -ExpandProperty Value
}
#endregion

#region Interactive Selection
function Show-InteractiveMenu {
    <#
    .SYNOPSIS
        Show an interactive menu with fuzzy filtering
    .DESCRIPTION
        Displays a list of items that can be filtered by typing.
        Use arrow keys to navigate, Enter to select, Escape to cancel.
    .PARAMETER Items
        Array of items to display
    .PARAMETER Title
        Title to show above the menu
    .PARAMETER CurrentItem
        The currently selected item (will be highlighted differently)
    .PARAMETER HighlightColor
        Color to use for highlighting the selected item
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Items,
        
        [Parameter()]
        [string]$Title = "Select an item",
        
        [Parameter()]
        [string]$CurrentItem = $null,
        
        [Parameter()]
        [string]$HighlightColor = "Cyan"
    )
    
    if ($Items.Count -eq 0) {
        Write-Host "No items to display" -ForegroundColor Yellow
        return $null
    }
    
    $filter = ""
    $selectedIndex = 0
    $maxVisible = [Math]::Min(15, $Host.UI.RawUI.WindowSize.Height - 5)
    $scrollOffset = 0
    
    # Save cursor position
    $startPosition = $Host.UI.RawUI.CursorPosition
    
    # Hide cursor
    $cursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false
    
    try {
        while ($true) {
            # Apply fuzzy filter
            if ([string]::IsNullOrEmpty($filter)) {
                $filteredItems = $Items
            } else {
                $filteredItems = @(Get-FuzzyMatches -WordToComplete $filter -Candidates $Items)
            }
            
            # Ensure selected index is valid
            if ($filteredItems.Count -eq 0) {
                $selectedIndex = 0
            } elseif ($selectedIndex -ge $filteredItems.Count) {
                $selectedIndex = $filteredItems.Count - 1
            }
            
            # Adjust scroll offset
            if ($selectedIndex -lt $scrollOffset) {
                $scrollOffset = $selectedIndex
            } elseif ($selectedIndex -ge $scrollOffset + $maxVisible) {
                $scrollOffset = $selectedIndex - $maxVisible + 1
            }
            
            # Move cursor to start position
            $Host.UI.RawUI.CursorPosition = $startPosition
            
            # Draw title and filter
            Write-Host "$Title " -ForegroundColor $HighlightColor -NoNewline
            Write-Host "(↑↓ navigate, Enter select, Esc cancel)" -ForegroundColor Gray
            Write-Host "Filter: " -NoNewline -ForegroundColor Yellow
            Write-Host $filter -NoNewline
            Write-Host ("_" + " " * 50) -ForegroundColor DarkGray  # Cursor indicator + clear rest of line
            Write-Host ""
            
            # Draw items
            $visibleCount = [Math]::Min($maxVisible, $filteredItems.Count)
            
            # Show scroll indicator at top if needed
            if ($scrollOffset -gt 0) {
                Write-Host "  ▲ more above" -ForegroundColor DarkGray
            } else {
                Write-Host (" " * 60)  # Clear line
            }
            
            for ($i = 0; $i -lt $maxVisible; $i++) {
                $itemIndex = $i + $scrollOffset
                if ($itemIndex -lt $filteredItems.Count) {
                    $item = $filteredItems[$itemIndex]
                    $isSelected = ($itemIndex -eq $selectedIndex)
                    $isCurrent = ($item -eq $CurrentItem)
                    
                    if ($isSelected) {
                        Write-Host "► " -ForegroundColor $HighlightColor -NoNewline
                        if ($isCurrent) {
                            Write-Host $item -ForegroundColor Green -BackgroundColor DarkGray -NoNewline
                            Write-Host " (current)" -ForegroundColor Green -NoNewline
                        } else {
                            Write-Host $item -ForegroundColor $HighlightColor -BackgroundColor DarkGray -NoNewline
                        }
                        Write-Host (" " * [Math]::Max(0, 50 - $item.Length))  # Clear rest of line
                    } else {
                        if ($isCurrent) {
                            Write-Host "* " -ForegroundColor Green -NoNewline
                            Write-Host $item -ForegroundColor Green -NoNewline
                            Write-Host " (current)" -ForegroundColor DarkGreen -NoNewline
                        } else {
                            Write-Host "  $item" -NoNewline
                        }
                        Write-Host (" " * [Math]::Max(0, 50 - $item.Length))  # Clear rest of line
                    }
                } else {
                    Write-Host (" " * 60)  # Clear line
                }
            }
            
            # Show scroll indicator at bottom if needed
            if ($scrollOffset + $maxVisible -lt $filteredItems.Count) {
                Write-Host "  ▼ more below ($($filteredItems.Count - $scrollOffset - $maxVisible) more)" -ForegroundColor DarkGray
            } else {
                Write-Host (" " * 60)  # Clear line
            }
            
            # Show count
            Write-Host ""
            Write-Host "$($filteredItems.Count) of $($Items.Count) items" -ForegroundColor DarkGray -NoNewline
            Write-Host (" " * 40)  # Clear rest of line
            
            # Read key
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            switch ($key.VirtualKeyCode) {
                13 {  # Enter
                    if ($filteredItems.Count -gt 0) {
                        # Clear the menu area
                        $Host.UI.RawUI.CursorPosition = $startPosition
                        for ($i = 0; $i -lt $maxVisible + 6; $i++) {
                            Write-Host (" " * 60)
                        }
                        $Host.UI.RawUI.CursorPosition = $startPosition
                        return $filteredItems[$selectedIndex]
                    }
                }
                27 {  # Escape
                    # Clear the menu area
                    $Host.UI.RawUI.CursorPosition = $startPosition
                    for ($i = 0; $i -lt $maxVisible + 6; $i++) {
                        Write-Host (" " * 60)
                    }
                    $Host.UI.RawUI.CursorPosition = $startPosition
                    return $null
                }
                38 {  # Up arrow
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                }
                40 {  # Down arrow
                    if ($selectedIndex -lt $filteredItems.Count - 1) {
                        $selectedIndex++
                    }
                }
                8 {  # Backspace
                    if ($filter.Length -gt 0) {
                        $filter = $filter.Substring(0, $filter.Length - 1)
                        $selectedIndex = 0
                        $scrollOffset = 0
                    }
                }
                default {
                    # Add character to filter if it's printable
                    $char = $key.Character
                    if ($char -match '[\w\-\.]') {
                        $filter += $char
                        $selectedIndex = 0
                        $scrollOffset = 0
                    }
                }
            }
        }
    } finally {
        # Restore cursor visibility
        [Console]::CursorVisible = $cursorVisible
    }
}

function Test-FzfAvailable {
    <#
    .SYNOPSIS
        Check if fzf is available on the system
    #>
    $null = Get-Command fzf -ErrorAction SilentlyContinue
    return $?
}

function Invoke-FzfSelection {
    <#
    .SYNOPSIS
        Use fzf for interactive selection
    .PARAMETER Items
        Array of items to select from
    .PARAMETER Header
        Header text to display
    .PARAMETER CurrentItem
        The currently selected item (will be marked)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Items,
        
        [Parameter()]
        [string]$Header = "Select an item",
        
        [Parameter()]
        [string]$CurrentItem = $null
    )
    
    # Mark current item if specified
    $displayItems = $Items | ForEach-Object {
        if ($_ -eq $CurrentItem) {
            "$_ (current)"
        } else {
            $_
        }
    }
    
    $selected = $displayItems | fzf --header $Header --height 40% --reverse
    
    if ($selected) {
        # Remove the " (current)" suffix if present
        return $selected -replace ' \(current\)$', ''
    }
    return $null
}
#endregion

#region Context Functions
function ct {
    <#
    .SYNOPSIS
        Switch or list Kubernetes contexts
    .DESCRIPTION
        Without arguments, lists all available contexts (current one highlighted).
        With an argument, switches to the specified context.
        With -Interactive, shows an interactive fuzzy-filterable menu.
    .PARAMETER Context
        The name of the context to switch to
    .PARAMETER Interactive
        Show an interactive menu to select the context
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Context,
        
        [Parameter()]
        [Alias("i")]
        [switch]$Interactive
    )
    
    $contexts = kubectl config get-contexts -o=name 2>$null | Sort-Object
    $currentContext = kubectl config current-context 2>$null
    
    if ($Interactive) {
        # Use fzf if available, otherwise fall back to custom menu
        if (Test-FzfAvailable) {
            $selected = Invoke-FzfSelection -Items $contexts -Header "Select Context" -CurrentItem $currentContext
        } else {
        $selected = Show-InteractiveMenu -Items $contexts -Title "Select Context" -CurrentItem $currentContext -HighlightColor "Red"
        }
        if ($selected) {
            kubectl config use-context $selected
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Switched to context: " -NoNewline
                Write-Host $selected -ForegroundColor $script:Colors.Red
            }
        } else {
            Write-Host "Selection cancelled" -ForegroundColor Yellow
        }
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($Context)) {
        # List all contexts with current one highlighted
        foreach ($ctx in $contexts) {
            if ($ctx -eq $currentContext) {
                Write-Host "* " -ForegroundColor Green -NoNewline
                Write-Host $ctx -ForegroundColor Green
            } else {
                Write-Host "  $ctx"
            }
        }
        return
    }
    
    # Actually switch the context using kubectl
    kubectl config use-context $Context
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Switched to context: " -NoNewline
        Write-Host $Context -ForegroundColor $script:Colors.Red
    }
}

# Tab completion for ct (with fuzzy matching)
Register-ArgumentCompleter -CommandName ct -ParameterName Context -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $contexts = kubectl config get-contexts -o=name 2>$null | Sort-Object
    $matches = Get-FuzzyMatches -WordToComplete $wordToComplete -Candidates $contexts
    $matches | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
#endregion

#region Namespace Functions
function ns {
    <#
    .SYNOPSIS
        Switch or list Kubernetes namespaces
    .DESCRIPTION
        Without arguments, lists all available namespaces (current one highlighted).
        With an argument, switches to the specified namespace.
        With -Interactive, shows an interactive fuzzy-filterable menu.
    .PARAMETER Namespace
        The name of the namespace to switch to
    .PARAMETER Interactive
        Show an interactive menu to select the namespace
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Namespace,
        
        [Parameter()]
        [Alias("i")]
        [switch]$Interactive
    )
    
    $namespaces = k get namespaces -o=jsonpath='{range .items[*].metadata.name}{@}{"\n"}{end}' 2>$null
    $nsList = $namespaces -split "`n" | Where-Object { $_ } | Sort-Object
    
    if ($Interactive) {
        # Use fzf if available, otherwise fall back to custom menu
        if (Test-FzfAvailable) {
            $selected = Invoke-FzfSelection -Items $nsList -Header "Select Namespace" -CurrentItem $script:KUBECTL_NAMESPACE
        } else {
        $selected = Show-InteractiveMenu -Items $nsList -Title "Select Namespace" -CurrentItem $script:KUBECTL_NAMESPACE -HighlightColor "Cyan"
        }
        if ($selected) {
            $script:KUBECTL_NAMESPACE = $selected
            Write-Host "Switched to namespace: " -NoNewline
            Write-Host $selected -ForegroundColor $script:Colors.Cyan
        } else {
            Write-Host "Selection cancelled" -ForegroundColor Yellow
        }
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($Namespace)) {
        # List all namespaces with current one highlighted
        foreach ($ns in $nsList) {
            if ($ns -eq $script:KUBECTL_NAMESPACE) {
                Write-Host "* " -ForegroundColor Cyan -NoNewline
                Write-Host $ns -ForegroundColor Cyan
            } else {
                Write-Host "  $ns"
            }
        }
        return
    }
    
    $script:KUBECTL_NAMESPACE = $Namespace
    Write-Host "Switched to namespace: " -NoNewline
    Write-Host $Namespace -ForegroundColor $script:Colors.Cyan
}

# Tab completion for ns (with fuzzy matching)
Register-ArgumentCompleter -CommandName ns -ParameterName Namespace -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $namespaces = kubectl get namespaces -o=jsonpath='{range .items[*].metadata.name}{@}{" "}{end}' 2>$null
    $nsList = $namespaces -split ' ' | Where-Object { $_ }
    $matches = Get-FuzzyMatches -WordToComplete $wordToComplete -Candidates $nsList
    $matches | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
#endregion

#region Kubectl Wrapper
function k {
    <#
    .SYNOPSIS
        kubectl wrapper that automatically includes namespace
    .DESCRIPTION
        Wraps kubectl to automatically include the current namespace.
        Context is managed by kubectl directly via 'ct' command.
    #>
    $kubectlArgs = @()
    
    if ($script:KUBECTL_NAMESPACE) {
        $kubectlArgs += "--namespace"
        $kubectlArgs += $script:KUBECTL_NAMESPACE
    }
    
    $kubectlArgs += $args
    
    & kubectl @kubectlArgs
}

# Tab completion for k (kubectl) with fuzzy matching
Register-ArgumentCompleter -CommandName k -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    
    # Get kubectl completions
    $commands = @('get', 'describe', 'create', 'apply', 'delete', 'scale', 'rollout', 'logs', 'exec', 'port-forward', 'top', 'edit', 'patch', 'label', 'annotate', 'expose', 'run', 'attach', 'cp', 'auth', 'debug', 'diff', 'kustomize', 'wait', 'autoscale', 'certificate', 'cluster-info', 'cordon', 'drain', 'taint', 'uncordon', 'config', 'plugin', 'version', 'api-resources', 'api-versions', 'explain')
    $resources = @('pods', 'po', 'services', 'svc', 'deployments', 'deploy', 'replicasets', 'rs', 'replicationcontrollers', 'rc', 'nodes', 'no', 'namespaces', 'ns', 'configmaps', 'cm', 'secrets', 'persistentvolumes', 'pv', 'persistentvolumeclaims', 'pvc', 'ingresses', 'ing', 'events', 'ev', 'daemonsets', 'ds', 'statefulsets', 'sts', 'jobs', 'cronjobs', 'cj', 'serviceaccounts', 'sa', 'endpoints', 'ep', 'limitranges', 'limits', 'resourcequotas', 'quota', 'horizontalpodautoscalers', 'hpa')
    
    $allCompletions = $commands + $resources
    $matches = Get-FuzzyMatches -WordToComplete $wordToComplete -Candidates $allCompletions
    $matches | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
#endregion

#region Common Action Functions
function Invoke-KDescribe { k describe @args }
function Invoke-KGet { k get @args }
function Invoke-KCreate { k create @args }
function Invoke-KApply { k apply @args }
function Invoke-KDelete { k delete @args }
function Invoke-KScale { k scale @args }
function Invoke-KRollout { k rollout @args }
function Invoke-KLogs { k logs @args }
function Invoke-KExplain { k explain @args }

Set-Alias -Name describe -Value Invoke-KDescribe -Scope Script
Set-Alias -Name get -Value Invoke-KGet -Scope Script
Set-Alias -Name create -Value Invoke-KCreate -Scope Script
Set-Alias -Name apply -Value Invoke-KApply -Scope Script
Set-Alias -Name delete -Value Invoke-KDelete -Scope Script
Set-Alias -Name scale -Value Invoke-KScale -Scope Script
Set-Alias -Name rollout -Value Invoke-KRollout -Scope Script
Set-Alias -Name logs -Value Invoke-KLogs -Scope Script
Set-Alias -Name explain -Value Invoke-KExplain -Scope Script
#endregion

#region Resource Query Functions
function pods { k get pods @args }
function services { k get svc @args }
function deployments { k get deployments @args }
function dep { k get deployments @args }
function replicasets { k get rs @args }
function replicationcontrollers { k get rc @args }
function rc { k get rc @args }
function nodes { k get nodes @args }
function limitranges { k get limitranges @args }
function limits { k get limitranges @args }
function events { k get events @args }
function persistentvolumes { k get pv @args }
function pv { k get pv @args }
function persistentvolumeclaims { k get pvc @args }
function pvc { k get pvc @args }
function namespaces { k get ns @args }
function ingresses { k get ing @args }
function ing { k get ing @args }
function configmaps { k get configmaps @args }
function secrets { k get secrets @args }
function statefulsets { k get sts @args }
function sts { k get sts @args }
function daemonsets { k get ds @args }
function ds { k get ds @args }
function jobs { k get jobs @args }
function cronjobs { k get cj @args }
function cj { k get cj @args }
#endregion

#region Extensions
function Reload-Extensions {
    <#
    .SYNOPSIS
        Reload the k8sps extensions file
    .DESCRIPTION
        Looks for and sources ~/.k8sps_extensions.ps1
    #>
    $extensionsPath = Join-Path $HOME ".k8sps_extensions.ps1"
    if (Test-Path $extensionsPath) {
        Write-Host "Sourcing $extensionsPath..."
        . $extensionsPath
    }
}
Set-Alias -Name reloadExtensions -Value Reload-Extensions -Scope Script
#endregion

#region Prompt
function Set-K8sPrompt {
    <#
    .SYNOPSIS
        Set the PowerShell prompt for k8sps
    #>
    function global:prompt {
        $ctx = kubectl config current-context 2>$null
        if (-not $ctx) { $ctx = "none" }
        $ns = if ($script:KUBECTL_NAMESPACE) { $script:KUBECTL_NAMESPACE } else { "none" }
        
        Write-Host "(" -NoNewline
        Write-Host $ctx -ForegroundColor Red -NoNewline
        Write-Host "/" -NoNewline
        Write-Host $ns -ForegroundColor Cyan -NoNewline
        Write-Host ") " -NoNewline
        Write-Host (Split-Path -Leaf (Get-Location)) -NoNewline
        Write-Host " " -NoNewline
        Write-Host "$" -ForegroundColor Magenta -NoNewline
        return " "
    }
}
#endregion

#region Utility Functions
function kexec {
    <#
    .SYNOPSIS
        Execute a command in a pod
    .PARAMETER Pod
        Name of the pod
    .PARAMETER Command
        Command to execute (defaults to /bin/sh)
    .PARAMETER Container
        Container name (optional)
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Pod,
        
        [Parameter(Position = 1)]
        [string]$Command = "/bin/sh",
        
        [Parameter()]
        [string]$Container
    )
    
    $execArgs = @("exec", "-it", $Pod)
    if ($Container) {
        $execArgs += "-c"
        $execArgs += $Container
    }
    $execArgs += "--"
    $execArgs += $Command
    
    k @execArgs
}

function kpf {
    <#
    .SYNOPSIS
        Port forward to a pod or service
    .PARAMETER Target
        Pod or service name (e.g., pod/mypod or svc/myservice)
    .PARAMETER Ports
        Port mapping (e.g., 8080:80)
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Ports
    )
    
    k port-forward $Target $Ports
}

function klogs {
    <#
    .SYNOPSIS
        Get logs from a pod with common options
    .PARAMETER Pod
        Name of the pod
    .PARAMETER Follow
        Follow the logs
    .PARAMETER Tail
        Number of lines to show
    .PARAMETER Container
        Container name (optional)
    .PARAMETER Previous
        Show previous container logs
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Pod,
        
        [Parameter()]
        [switch]$Follow,
        
        [Parameter()]
        [int]$Tail = 100,
        
        [Parameter()]
        [string]$Container,
        
        [Parameter()]
        [switch]$Previous
    )
    
    $logArgs = @("logs", $Pod, "--tail=$Tail")
    if ($Follow) { $logArgs += "-f" }
    if ($Container) { $logArgs += "-c"; $logArgs += $Container }
    if ($Previous) { $logArgs += "-p" }
    
    k @logArgs
}

function kwatch {
    <#
    .SYNOPSIS
        Watch resources (like kubectl get -w)
    .PARAMETER Resource
        Resource type to watch (e.g., pods, deployments)
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Resource
    )
    
    k get $Resource -w @args
}

function kdesc {
    <#
    .SYNOPSIS
        Describe a resource
    .PARAMETER Resource
        Resource type
    .PARAMETER Name
        Resource name
    #>
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Resource,
        
        [Parameter(Position = 1)]
        [string]$Name
    )
    
    if ($Name) {
        k describe $Resource $Name
    } else {
        k describe $Resource
    }
}
#endregion

#region Initialization
function Initialize-K8sps {
    <#
    .SYNOPSIS
        Initialize k8sps environment
    #>
    Clear-Host
    
    # Banner
    Write-Host ""
    Write-Host "Welcome to k" -ForegroundColor Magenta -NoNewline
    Write-Host "8" -ForegroundColor Red -NoNewline
    Write-Host "sps" -ForegroundColor Magenta
    Write-Host ""
    
    # Check for kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: kubectl not found in PATH" -ForegroundColor Red
        Write-Host "Please install kubectl and ensure it's in your PATH"
        return $false
    }
    
    Write-Host "Gathering current kubectl state..."
    
    # Get current context from kubectl (context is managed by kubectl directly)
    $currentContext = kubectl config current-context 2>$null
    if (-not $currentContext) {
        $currentContext = "none"
    }
    
    # Set default namespace
    $script:KUBECTL_NAMESPACE = if ($env:DEFAULT_NAMESPACE) { $env:DEFAULT_NAMESPACE } else { "default" }
    
    Write-Host "Setting up aliases and functions..."
    
    # Set up the prompt
    # Set-K8sPrompt
    
    # Load extensions
    Reload-Extensions
    
    Write-Host ""
    Write-Host "Context: " -NoNewline
    Write-Host $currentContext -ForegroundColor Red
    Write-Host "Namespace: " -NoNewline
    Write-Host $script:KUBECTL_NAMESPACE -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Type 'k8sps-help' for a list of available commands"
    Write-Host ""
    
    return $true
}

function k8sps-help {
    <#
    .SYNOPSIS
        Display help for k8sps commands
    #>
    Write-Host ""
    Write-Host "k8sps Commands" -ForegroundColor Magenta
    Write-Host "==============" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Context/Namespace:" -ForegroundColor Yellow
    Write-Host "  ct [context]     - List or switch contexts"
    Write-Host "  ct -i            - Interactive context selection with fuzzy filtering"
    Write-Host "  ns [namespace]   - List or switch namespaces"
    Write-Host "  ns -i            - Interactive namespace selection with fuzzy filtering"
    Write-Host ""
    Write-Host "kubectl Wrapper:" -ForegroundColor Yellow
    Write-Host "  k <args>         - kubectl with context/namespace"
    Write-Host ""
    Write-Host "Common Actions:" -ForegroundColor Yellow
    Write-Host "  describe, get, create, apply, delete, scale, rollout, logs, explain"
    Write-Host ""
    Write-Host "Resource Queries:" -ForegroundColor Yellow
    Write-Host "  pods, services, deployments/dep, replicasets, rc, nodes"
    Write-Host "  limitranges/limits, events, pv, pvc, namespaces"
    Write-Host "  ingresses/ing, configmaps, secrets, statefulsets/sts"
    Write-Host "  daemonsets/ds, jobs, cronjobs/cj"
    Write-Host ""
    Write-Host "Utilities:" -ForegroundColor Yellow
    Write-Host "  kexec <pod> [cmd]           - Execute command in pod"
    Write-Host "  kpf <target> <ports>        - Port forward"
    Write-Host "  klogs <pod> [-Follow] [-Tail n] [-Container c] [-Previous]"
    Write-Host "  kwatch <resource>           - Watch resources"
    Write-Host "  kdesc <resource> [name]     - Describe resource"
    Write-Host ""
    Write-Host "Extensions:" -ForegroundColor Yellow
    Write-Host "  reloadExtensions  - Reload ~/.k8sps_extensions.ps1"
    Write-Host ""
}
#endregion

# Auto-initialize when script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $initialized = Initialize-K8sps
    if (-not $initialized) {
        Write-Host "Failed to initialize k8sps" -ForegroundColor Red
    }
}

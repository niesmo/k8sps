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

#region Context Functions
function ct {
    <#
    .SYNOPSIS
        Switch or list Kubernetes contexts
    .DESCRIPTION
        Without arguments, lists all available contexts (current one highlighted).
        With an argument, switches to the specified context.
    .PARAMETER Context
        The name of the context to switch to
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Context
    )
    
    if ([string]::IsNullOrWhiteSpace($Context)) {
        # List all contexts with current one highlighted
        $contexts = kubectl config get-contexts -o=name 2>$null | Sort-Object
        $currentContext = kubectl config current-context 2>$null
        
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
    .PARAMETER Namespace
        The name of the namespace to switch to
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Namespace
    )
    
    if ([string]::IsNullOrWhiteSpace($Namespace)) {
        # List all namespaces with current one highlighted
        $namespaces = k get namespaces -o=jsonpath='{range .items[*].metadata.name}{@}{"\n"}{end}' 2>$null
        $nsList = $namespaces -split "`n" | Where-Object { $_ } | Sort-Object
        
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
    Write-Host "  ns [namespace]   - List or switch namespaces"
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

# k8sps Extensions Example
# Place this file at ~/.k8sps_extensions.ps1 to customize your k8sps experience

# Displays all nodes in the cluster including kubernetes version info
function nodes {
    k get nodes -o=custom-columns=Name:.metadata.name,Kubelet:.status.nodeInfo.kubeletVersion,Proxy:.status.nodeInfo.kubeProxyVersion @args
}

# Runs a busybox container (optionally selecting a specific node to run on)
# and shells into it.
function busybox {
    param(
        [Parameter(Position = 0)]
        [string]$NodeName
    )
    
    # Delete existing busybox pod if it exists
    k delete po/busybox --ignore-not-found 2>$null
    
    $overrideParam = ""
    if ($NodeName) {
        Write-Host "Restricting pod to node: $NodeName"
        $overrideParam = '{ "spec": { "nodeSelector": { "kubernetes.io/hostname": "' + $NodeName + '" } } }'
        k run -i --tty busybox --image=busybox --restart=Never --overrides=$overrideParam -- sh
    } else {
        k run -i --tty busybox --image=busybox --restart=Never -- sh
    }
}

# Quick pod status overview
function pod-status {
    k get pods -o=custom-columns='NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
}

# Get all pods not in Running state
function troubled-pods {
    k get pods --field-selector=status.phase!=Running @args
}

# Quick resource usage for pods
function pod-resources {
    k top pods @args
}

# Quick resource usage for nodes
function node-resources {
    k top nodes @args
}

# Get all images used in the current namespace
function pod-images {
    k get pods -o=custom-columns='POD:.metadata.name,IMAGE:.spec.containers[*].image'
}

# Quickly scale a deployment
function kscale {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Deployment,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [int]$Replicas
    )
    
    k scale deployment $Deployment --replicas=$Replicas
}

# Restart a deployment by setting a new annotation
function krestart {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Deployment
    )
    
    k rollout restart deployment $Deployment
}

# Get events sorted by time
function kevents {
    k get events --sort-by='.lastTimestamp' @args
}

# Watch events in real-time
function kwatch-events {
    k get events -w @args
}

# Get all resources in the current namespace
function kall {
    k get all @args
}

# Decode a secret value
function kdecode-secret {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SecretName,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Key
    )
    
    $encoded = k get secret $SecretName -o=jsonpath="{.data.$Key}"
    if ($encoded) {
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))
    } else {
        Write-Host "Key '$Key' not found in secret '$SecretName'" -ForegroundColor Red
    }
}

Write-Host "k8sps extensions loaded!" -ForegroundColor Green

# k8sps

A PowerShell shell wrapper including aliases and functions for kubectl that makes it easy to navigate between and execute commands on different Kubernetes clusters and namespaces.

This is a PowerShell port of [k8sh](https://github.com/Comcast/k8sh), designed to provide the same functionality for Windows PowerShell users.

## Requirements

- PowerShell 5.1 or later (PowerShell 7+ recommended)
- kubectl installed and in your PATH

## Getting Started

### Running k8sps

You can run k8sps in two ways:

**Option 1: Run directly**
```powershell
.\k8sps.ps1
```

**Option 2: Dot-source to load into current session**
```powershell
. .\k8sps.ps1
```

To make k8sps available from anywhere, add the script directory to your PATH or copy it to a directory already in your PATH.

<details>
<summary><strong>Adding to Your PowerShell Profile</strong></summary>

To have k8sps automatically available in every PowerShell session, add it to your PowerShell profile:

1. **Find your profile path:**
   ```powershell
   $PROFILE
   ```

2. **Create the profile if it doesn't exist:**
   ```powershell
   if (!(Test-Path -Path $PROFILE)) {
       New-Item -ItemType File -Path $PROFILE -Force
   }
   ```

3. **Add k8sps to your profile:**
   ```powershell
   # Open your profile in your default editor
   notepad $PROFILE
   
   # Or with VS Code
   code $PROFILE
   ```

4. **Add one of the following lines to your profile:**

   ```powershell
   # Option A: Dot-source to load all functions into your session
   . "C:\path\to\k8sps.ps1"
   
   # Option B: Create an alias to run k8sps on demand
   Set-Alias -Name k8sps -Value "C:\path\to\k8sps.ps1"
   ```

   Replace `C:\path\to\k8sps.ps1` with the actual path to your k8sps.ps1 file.

5. **Reload your profile or restart PowerShell:**
   ```powershell
   . $PROFILE
   ```

> **TIP:** If you want the k8sps prompt to be enabled automatically, uncomment the `Set-K8sPrompt` line in the `Initialize-K8sps` function, or add `Set-K8sPrompt` to your profile after sourcing k8sps.

</details>

<br />
k8sps will automatically detect your current kubectl configuration to determine your current Kubernetes context and namespace.

## Context and Namespace Commands

k8sps automatically keeps track of the current context and namespace you are operating in. These are displayed when starting up k8sps.

### Switch contexts

```powershell
ct <context_to_switch_to>
```

### List available contexts

```powershell
ct
```
The current context is highlighted with `*` in green.

### Switch namespaces

```powershell
ns <namespace_to_switch_to>
```

### List available namespaces

```powershell
ns
```
The current namespace is highlighted with `*` in cyan.

### Interactive Selection

Both `ct` and `ns` support an interactive mode with fuzzy filtering. Use the `-i` (or `-Interactive`) flag to open an interactive picker:

```powershell
ct -i    # Interactive context selection
ns -i    # Interactive namespace selection
```

**Interactive Mode Controls:**

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate up/down through the list |
| Type characters | Fuzzy filter the list |
| `Backspace` | Remove last filter character |
| `Enter` | Select the highlighted item |
| `Escape` | Cancel selection |

**Features:**
- **Fuzzy filtering** - Type to filter items (e.g., type `kbs` to match `kube-system`)
- **Current item indicator** - The currently active context/namespace is marked with `(current)` in green
- **Scroll support** - Long lists show scroll indicators (`▲ more above` / `▼ more below`)
- **Item count** - Shows filtered vs total count at the bottom

> **NOTE:** When changing the context, the change is made globally to kubectl using `kubectl config use-context`. The namespace, however, is kept track of by k8sps. The `k` command wrapper automatically includes the namespace that is currently selected within k8sps.

## Aliases and Functions

When inside k8sps, the `k` function wraps `kubectl` to automatically include the namespace that is currently selected.

### k

**k** is an easy shorthand for `kubectl` with automatic namespace inclusion.

### Common Actions

Shorthands for common kubectl actions:

| Alias | Command |
|-------|---------|
| `describe` | k describe |
| `get` | k get |
| `create` | k create |
| `apply` | k apply |
| `delete` | k delete |
| `scale` | k scale |
| `rollout` | k rollout |
| `logs` | k logs |
| `explain` | k explain |

### Resource Query Functions

Instead of typing out `k get pods/services/deployments/etc`, simply use these functions:

| Function | Resource |
|----------|----------|
| `pods` | pods |
| `services` | services |
| `deployments` / `dep` | deployments |
| `replicasets` | replicasets |
| `replicationcontrollers` / `rc` | replicationcontrollers |
| `nodes` | nodes |
| `limitranges` / `limits` | limitranges |
| `events` | events |
| `persistentvolumes` / `pv` | persistentvolumes |
| `persistentvolumeclaims` / `pvc` | persistentvolumeclaims |
| `namespaces` | namespaces |
| `ingresses` / `ing` | ingresses |
| `configmaps` | configmaps |
| `secrets` | secrets |
| `statefulsets` / `sts` | statefulsets |
| `daemonsets` / `ds` | daemonsets |
| `jobs` | jobs |
| `cronjobs` / `cj` | cronjobs |

All functions accept additional arguments that are passed to kubectl:
```powershell
pods -o wide
deployments -l app=myapp
```

## Utility Functions

k8sps includes several PowerShell-specific utility functions:

### kexec

Execute a command in a pod (defaults to `/bin/sh`):
```powershell
kexec <pod-name>
kexec <pod-name> /bin/bash
kexec <pod-name> -Container <container-name>
```

### kpf

Port forward to a pod or service:
```powershell
kpf pod/mypod 8080:80
kpf svc/myservice 3000:80
```

### klogs

Get logs with common options:
```powershell
klogs <pod-name>
klogs <pod-name> -Follow
klogs <pod-name> -Tail 50
klogs <pod-name> -Container <container-name>
klogs <pod-name> -Previous
```

### kwatch

Watch resources in real-time:
```powershell
kwatch pods
kwatch deployments
```

### kdesc

Describe resources:
```powershell
kdesc pod <pod-name>
kdesc deployment <deployment-name>
```

## Tab Completion

The `ct`, `ns`, and `k` commands all support tab completion with **fuzzy matching**.

### Fuzzy Matching

Tab completion supports fuzzy matching, so you don't need to type exact prefixes:

| You type | Matches |
|----------|---------|
| `kbs` | kube-system |
| `dft` | default |
| `dpl` | deployments |
| `pf` | port-forward |

Matches are prioritized:
1. **Exact match** - highest priority
2. **Prefix match** - starts with your input
3. **Contains match** - contains your input
4. **Fuzzy match** - characters appear in order

## Extensions

On startup, k8sps looks for a `.k8sps_extensions.ps1` file in your home directory (`$HOME`). If found, it is dot-sourced, allowing you to define your own aliases and functions.

### Reload extensions

To reload extensions while in a k8sps session:
```powershell
reloadExtensions
```

### Example extensions

See `examples/k8sps_extensions.ps1` for examples including:

- Custom node display with version info
- Busybox container launcher
- Pod status overview
- Troubled pods finder
- Resource usage commands
- Secret decoder
- And more!

To use the examples, copy to your home directory:
```powershell
Copy-Item .\examples\k8sps_extensions.ps1 $HOME\.k8sps_extensions.ps1
```

## Help

For a quick reference of available commands:
```powershell
k8sps-help
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DEFAULT_NAMESPACE` | Initial namespace when k8sps starts | `default` |

## License

See [LICENSE](LICENSE) file.

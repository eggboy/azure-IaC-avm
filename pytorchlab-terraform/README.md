# pytorchlab-terraform

A simple Azure GPU VM for PyTorch development and Jupyter Notebook, built with [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) and Terraform. Designed for remote ML experimentation — SSH in from VS Code Remote-SSH, run Jupyter notebooks, and leverage NVIDIA T4 GPU with CUDA.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Resource Group: rg-pytorchlab-dev-eastus2                  │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  VNet: vnet-pytorchlab-dev-eastus2  (10.0.0.0/16)     │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Subnet: snet-vm  (10.0.0.0/24)                 │  │  │
│  │  │  NSG: Allow SSH (port 22) from allowed IP        │  │  │
│  │  │                                                  │  │  │
│  │  │  ┌────────────────────────────────────────────┐  │  │  │
│  │  │  │  VM: Standard_NC4as_T4_v3                 │  │  │  │
│  │  │  │  • Ubuntu 24.04 LTS                       │  │  │  │
│  │  │  │  • NVIDIA T4 GPU (16 GB VRAM)             │  │  │  │
│  │  │  │  • CUDA drivers (Azure VM extension)      │  │  │  │
│  │  │  │  • PyTorch + Jupyter (cloud-init)          │  │  │  │
│  │  │  │  • 176 GB temp disk (NVMe SSD at /mnt)    │  │  │  │
│  │  │  │  • Public IP + SSH key auth                │  │  │  │
│  │  │  └────────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | Details |
|---|---|
| **GPU VM** | `Standard_NC4as_T4_v3` — 4 vCPUs, 28 GB RAM, NVIDIA T4 16 GB VRAM, 176 GB temp disk |
| **OS** | Ubuntu 24.04 LTS Gen2 with NVIDIA GPU driver extension |
| **Software** | CUDA toolkit, Miniconda, PyTorch (CUDA 12.4), JupyterLab |
| **Temp Disk** | 176 GB local NVMe SSD at `/mnt` — used for `TMPDIR`, `TORCH_HOME`, `PIP_CACHE_DIR`, with `~/data` and `~/checkpoints` symlinks |
| **Networking** | Single VNet + subnet, NSG restricts SSH to `allowed_source_ip` |
| **Auth** | SSH public key only (password disabled), system-assigned managed identity |

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.9
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (authenticated via `az login`)
- An SSH key pair (default: `~/.ssh/id_rsa.pub`)
- An Azure subscription with GPU quota for `Standard_NC4as_T4_v3` in the target region
- [VS Code](https://code.visualstudio.com/) with the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) and [Jupyter](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter) extensions

## Deploy

```bash
cd pytorchlab-terraform/

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

By default, SSH is open to all IPs. **Restrict it to your IP:**

```bash
terraform apply -var 'allowed_source_ip=203.0.113.1'
```

Use a different SSH key:

```bash
terraform apply -var 'ssh_public_key_file=~/.ssh/id_ed25519.pub'
```

After deployment, Terraform outputs the connection details:

```
public_ip_address = "20.x.x.x"
ssh_command       = "ssh azureuser@20.x.x.x"
vscode_remote_ssh = "code --remote ssh-remote+azureuser@20.x.x.x /home/azureuser"
```

> **Note:** Cloud-init runs on first boot and takes ~10 minutes to install CUDA drivers, PyTorch, and Jupyter. Check progress with:
> ```bash
> ssh azureuser@<IP> tail -f /var/log/cloud-init-output.log
> ```

## Connecting with VS Code + Jupyter

This is the recommended workflow — VS Code handles everything over SSH, no need to expose port 8888.

### Step 1: Add the VM to your SSH config

Add this to `~/.ssh/config`:

```
Host pytorchlab
    HostName <public-ip-from-terraform-output>
    User azureuser
    IdentityFile ~/.ssh/id_rsa
```

### Step 2: Connect with VS Code Remote-SSH

1. Open VS Code
2. Press `Cmd+Shift+P` (or `Ctrl+Shift+P`) → **Remote-SSH: Connect to Host…**
3. Select `pytorchlab`
4. VS Code opens a new window connected to the VM

Or use the CLI shortcut from the Terraform output:

```bash
code --remote ssh-remote+pytorchlab /home/azureuser
```

### Step 3: Run Jupyter Notebooks

1. In the VS Code remote window, open or create a `.ipynb` file
2. VS Code Jupyter extension detects the notebook and prompts you to select a kernel
3. Select the **Python (Miniconda)** kernel at `~/miniconda3/bin/python`
4. Run cells — they execute on the GPU VM, results display in VS Code on your laptop

That's it — no Jupyter server to start, no ports to forward. VS Code manages the Jupyter kernel process over SSH automatically.

### Alternative: Local Notebook + Remote GPU Kernel

Keep notebook files on your laptop and only run the kernel on the Azure GPU VM. One command opens the SSH tunnel and starts Jupyter:

```bash
ssh -L 8888:localhost:8888 azureuser@<public-ip> \
  "~/miniconda3/bin/jupyter lab --no-browser --port=8888 --ip=127.0.0.1"
```

Jupyter prints a URL with a token, e.g. `http://localhost:8888/lab?token=abc123...`. Then in VS Code:

1. Open a local `.ipynb` file
2. Click **Select Kernel** → **Existing Jupyter Server…**
3. Paste the URL from the terminal
4. Select the **Python 3** kernel

Cells execute on the Azure GPU while the notebook stays local. The NSG does **not** need to allow port 8888 — the SSH tunnel carries all traffic over port 22.

> **Tip:** With the SSH config alias from Step 1, the command simplifies to:
> ```bash
> ssh -L 8888:localhost:8888 pytorchlab \
>   "~/miniconda3/bin/jupyter lab --no-browser --port=8888 --ip=127.0.0.1"
> ```

## Temp Disk Layout

The 176 GB local NVMe SSD (`/mnt`) is configured for fast I/O:

| Path | Purpose |
|---|---|
| `/mnt/data` → `~/data` | Training data, datasets |
| `/mnt/checkpoints` → `~/checkpoints` | Model checkpoints |
| `/mnt/cache` | pip cache, torch hub cache |
| `/mnt/tmp` | `TMPDIR` for scratch files |

> ⚠️ **Temp disk is ephemeral** — data is lost on VM deallocation. Store important files on the OS disk or Azure Storage.

## Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `ssh_public_key_file` | string | `~/.ssh/id_rsa.pub` | Path to SSH public key file |
| `admin_username` | string | `azureuser` | VM admin username |
| `allowed_source_ip` | string | `*` | Source IP/CIDR for SSH NSG rule |
| `enable_telemetry` | bool | `true` | AVM telemetry toggle |
| `environment` | string | `dev` | Environment name (dev/stg/prd) |
| `location` | string | `eastus2` | Azure region |
| `os_disk_size_gb` | number | `128` | OS disk size in GB |
| `subnet_address_prefix` | string | `10.0.0.0/24` | VM subnet CIDR |
| `tags` | map(string) | `{}` | Resource tags |
| `vm_size` | string | `Standard_NC4as_T4_v3` | GPU VM SKU |
| `vm_zone` | string | `null` | Availability zone |
| `vnet_address_space` | list(string) | `["10.0.0.0/16"]` | VNet CIDR |
| `workload` | string | `pytorchlab` | Workload name for resource naming |

## Clean Up

```bash
terraform destroy
```

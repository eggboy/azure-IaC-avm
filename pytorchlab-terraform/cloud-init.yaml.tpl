#cloud-config
package_update: true
package_upgrade: true

packages:
  - build-essential
  - git
  - curl
  - wget
  - unzip

write_files:
  - path: /opt/setup-pytorch.sh
    permissions: "0755"
    content: |
      #!/bin/bash
      set -euo pipefail

      ADMIN_USER="${admin_username}"
      HOME_DIR="/home/$ADMIN_USER"
      TEMP_DISK="/mnt"

      # --- Temp disk setup (176 GB local NVMe SSD) ---
      # Azure auto-mounts the resource disk at /mnt; leverage it for fast I/O
      mkdir -p "$TEMP_DISK/data" "$TEMP_DISK/cache" "$TEMP_DISK/tmp" "$TEMP_DISK/checkpoints"
      chown -R "$ADMIN_USER:$ADMIN_USER" "$TEMP_DISK/data" "$TEMP_DISK/cache" "$TEMP_DISK/tmp" "$TEMP_DISK/checkpoints"

      # Symlink common working directories into the user's home
      sudo -u "$ADMIN_USER" ln -sfn "$TEMP_DISK/data" "$HOME_DIR/data"
      sudo -u "$ADMIN_USER" ln -sfn "$TEMP_DISK/checkpoints" "$HOME_DIR/checkpoints"

      # Write environment variables so PyTorch and pip use the fast temp disk
      cat >> "$HOME_DIR/.bashrc" <<'ENVEOF'

      # --- Temp disk (local NVMe SSD, 176 GB) ---
      export TMPDIR=/mnt/tmp
      export PIP_CACHE_DIR=/mnt/cache/pip
      export XDG_CACHE_HOME=/mnt/cache
      export TORCH_HOME=/mnt/cache/torch
      ENVEOF
      chown "$ADMIN_USER:$ADMIN_USER" "$HOME_DIR/.bashrc"

      # --- Miniconda ---
      echo "=== Installing Miniconda ==="
      wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
      sudo -u "$ADMIN_USER" bash /tmp/miniconda.sh -b -p "$HOME_DIR/miniconda3"
      rm /tmp/miniconda.sh
      sudo -u "$ADMIN_USER" "$HOME_DIR/miniconda3/bin/conda" init bash

      # --- PyTorch + Jupyter ---
      echo "=== Installing PyTorch with CUDA support ==="
      sudo -u "$ADMIN_USER" "$HOME_DIR/miniconda3/bin/pip" install \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu124

      echo "=== Installing Jupyter ==="
      sudo -u "$ADMIN_USER" "$HOME_DIR/miniconda3/bin/pip" install \
        jupyterlab notebook ipykernel

      # Mark setup complete
      touch "$HOME_DIR/.setup-complete"
      chown "$ADMIN_USER:$ADMIN_USER" "$HOME_DIR/.setup-complete"
      echo "=== PyTorch + Jupyter setup complete ==="

runcmd:
  - /opt/setup-pytorch.sh

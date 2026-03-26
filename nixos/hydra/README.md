# Hydra setup notes

This host expects the following filesystem labels:

- `/` -> label `nixos` (`ext4`)
- `/boot` -> label `boot` (`vfat`)
- `/data` -> label `data` (`ext4`)

These labels match:
- `nixos/hydra/hardware-configuration.nix` for `/` and `/boot`
- `nixos/hydra/configuration.nix` for `/data`

## Disk partitioning (two-disk example)

WARNING: These commands wipe disks.

Assumed devices:
- system disk: `/dev/nvme0n1`
- data disk: `/dev/nvme1n1`

Check disk names first:

```bash
lsblk -o NAME,SIZE,TYPE,MODEL
```

Partition and format system disk (EFI + root):

```bash
sudo sgdisk --zap-all /dev/nvme0n1
sudo parted -s /dev/sda mklabel gpt
sudo parted -s /dev/sda mkpart ESP fat32 1MiB 1025MiB
sudo parted -s /dev/sda set 1 esp on
sudo parted -s /dev/sda mkpart nixos ext4 1025MiB 100%

sudo mkfs.vfat -F32 -n boot /dev/sda1
sudo mkfs.ext4 -L nixos /dev/sda2
```

Partition and format data disk:

```bash
sudo sgdisk --zap-all /dev/nvme1n1
sudo parted -s /dev/nvme0n1 mklabel gpt
sudo parted -s /dev/nvme0n1 mkpart data ext4 1MiB 100%
sudo mkfs.ext4 -L data /dev/nvme0n1p1
```

## Mount before install

```bash
sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot /mnt/data
sudo mount /dev/disk/by-label/boot /mnt/boot
sudo mount /dev/disk/by-label/data /mnt/data
```

Verify labels:

```bash
lsblk -f
```

## Install command

After cloning this repo to `/mnt/etc/nixos`, install with:

```bash
sudo nixos-install --flake /mnt/etc/nixos#hydra
```

## Fireactions on hydra

`hydra` is configured to run GitHub Actions runners with `nixos-fireactions`.

Before first switch, update:
- `services.fireactions.pools[0].runner.organization` in `nixos/hydra/fireactions.nix`

Required runtime secrets:
- `/var/lib/hydra-secrets/github-app-id`
- `/var/lib/hydra-secrets/github-app-key`

These should contain your GitHub App ID and private key.

## MinIO on hydra

`hydra` also imports `nixos/hydra/minio.nix` for a local S3-compatible server.

Current defaults:
- S3 API: `0.0.0.0:9000`
- Console: `127.0.0.1:9001`
- Data dir: `/data/minio`
- Credentials file: `/var/lib/hydra-secrets/minio-root`

`/var/lib/hydra-secrets/minio-root` must contain:

```bash
MINIO_ROOT_USER=...
MINIO_ROOT_PASSWORD=...
```

Create the directory and set ownership/permissions:

```bash
sudo install -d -m 700 -o root -g root /var/lib/hydra-secrets
sudo chmod 600 /var/lib/hydra-secrets/github-app-id /var/lib/hydra-secrets/github-app-key /var/lib/hydra-secrets/minio-root
```

# NVIDIA 470.xx Legacy Driver for Linux Kernel 6.12+

Patches to build the NVIDIA 470.xx legacy driver (last to support **Kepler GPUs**: GTX 600/700 series) against Linux kernel 6.8+.

## Why?

- NVIDIA dropped Kepler support after driver 470.xx
- Driver 470.xx won't compile against kernel 6.8+ due to removed kernel APIs
- This bridges the gap

## Affected GPUs

All NVIDIA Kepler GPUs (GeForce 600/700 series), including but not limited to:
GTX 660, GTX 660 Ti, GTX 670, GTX 680, GTX 760, GTX 770, GTX 780, GTX Titan

## What's Patched

| Patch | File(s) | Fix |
|-------|---------|-----|
| `001-follow-pfn` | `os-mlock.c`, `nvidia.Kbuild`, `conftest.sh` | `follow_pfn`/`unsafe_follow_pfn` removed in kernel 6.8+ |
| `002-conftest-gcc-flags` | `conftest.sh` | GCC 12+ `-Werror=implicit-function-declaration` |
| `003-drm-compat` | `nvidia-drm-drv.c` | DRM `output_poll_changed` removed, `FOP_UNSIGNED_OFFSET` moved (6.12) |
| `004-kbuild-symlink` | `nvidia.Kbuild`, `nvidia-modeset.Kbuild` | kbuild CWD symlink fix |
| `005-xorg-config` | `20-nvidia.conf` | Xorg OutputConfig for nvidia-drm |

## How to Apply

### Automated (recommended)
```bash
# Download NVIDIA 470.256.02 driver
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/470.256.02/NVIDIA-Linux-x86_64-470.256.02.run

# Extract
sh NVIDIA-Linux-x86_64-470.256.02.run --extract-only
cd NVIDIA-Linux-x86_64-470.256.02

# Apply patches
for p in ../001-follow-pfn.patch ../002-conftest-gcc-flags.patch \
         ../003-drm-compat.patch ../004-kbuild-symlink.patch; do
    patch -p1 < "$p"
done

# Build kernel modules
cd kernel
make KERNEL_UNAME=$(uname -r) modules -j$(nproc)

# Install modules
sudo mkdir -p /lib/modules/$(uname -r)/extra
sudo cp *.ko /lib/modules/$(uname -r)/extra/
sudo depmod -a $(uname -r)

# Install userspace
sudo cp ../nvidia-smi /usr/bin/
sudo cp ../lib*.so* /usr/lib/x86_64-linux-gnu/
sudo ldconfig

# Blacklist nouveau
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf

# Module autoloading
echo -e "nvidia\nnvidia-modeset\nnvidia-drm\nnvidia-uvm" | sudo tee /etc/modules-load.d/nvidia.conf

# Xorg config
sudo mkdir -p /etc/X11/xorg.conf.d
sudo cp ../20-nvidia.conf /etc/X11/xorg.conf.d/

# Update initramfs
sudo update-initramfs -u

# Reboot
sudo reboot
```

## Tested On

| Component | Version |
|-----------|---------|
| GPU | NVIDIA GeForce GTX 660 (GK106) |
| Driver | 470.256.02 |
| Kernel | 6.12.48+deb13 |
| Distro | LMDE 7 (gigi) / Debian Trixie |
| GCC | 14.x |

## Known Limitations

- `os_lookup_user_io_memory()` (IO-memory PTE lookup) fails — only affects user-space IO mappings, not desktop/rendering
- `nvidia-drm.modeset=1` recommended as kernel parameter on 6.12+
- Will need re-patching for kernel updates (no DKMS auto-rebuild)

## Credits

- [joanbm/nvidia-470xx-linux-mainline](https://github.com/joanbm/nvidia-470xx-linux-mainline) — comprehensive patch collection
- Debian Salsa [nvidia-graphics-drivers](https://salsa.debian.org/nvidia-team/nvidia-graphics-drivers/-/commits/tesla-470/main) tesla-470 branch
- Joan Bruguera Micó — DRM 6.12 compat patches

## License

NVIDIA's driver is proprietary. The patches here are provided as-is for educational purposes.

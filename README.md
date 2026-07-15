# NVIDIA 470.xx Legacy Driver for Linux Kernel 6.8+

Patches to build the NVIDIA 470.xx legacy driver (last to support **Kepler GPUs**: GTX 600/700 series) against Linux kernel 6.8+.

## Why?

- NVIDIA dropped Kepler support after driver 470.xx
- Driver 470.xx won't compile against kernel 6.8+ due to removed kernel APIs
- This bridges the gap

## Affected GPUs

All NVIDIA Kepler GPUs (GeForce 600/700 series), including but not limited to:
GTX 660, GTX 660 Ti, GTX 670, GTX 680, GTX 760, GTX 770, GTX 780, GTX Titan

## Quick Start

```bash
git clone https://github.com/Peterplime/nvidia-470xx-kernel-6.12-patches.git
cd nvidia-470xx-kernel-6.12-patches
./build.sh --install
sudo reboot
```

Or build a `.deb` package:

```bash
./build.sh --deb
sudo dpkg -i nvidia-470xx-470.256.02_amd64.deb
sudo reboot
```

## Build Script

The `build.sh` script handles everything: download, patch, build, and install.

```
./build.sh              Build kernel modules only
./build.sh --install    Build + install modules, userspace, and system config
./build.sh --deb        Build + package as .deb (requires dpkg-deb)
./build.sh --clean      Remove downloaded source and build artifacts
./build.sh --help       Show all options
```

## Forking for Other GPUs / Driver Versions

This repo is designed to be forked. To adapt it for a different NVIDIA driver or kernel version:

1. **Edit `build.sh`** — change `DRIVER_VERSION` and `DRIVER_URL` at the top
2. **Add or remove `.patch` files** in this directory
3. **Update the `PATCHES` array** in `build.sh` to list your patches in order
4. **Test** — run `./build.sh` and fix any new compilation errors

## What's Patched

| Patch | File(s) | Fix |
|-------|---------|-----|
| `001-follow-pfn` | `os-mlock.c`, `nvidia.Kbuild`, `conftest.sh` | `follow_pfn`/`unsafe_follow_pfn` removed in kernel 6.8+ |
| `002-conftest-gcc-flags` | `conftest.sh` | GCC 12+ `-Werror=implicit-function-declaration` |
| `003-drm-compat` | `nvidia-drm-drv.c` | DRM `output_poll_changed` removed, `FOP_UNSIGNED_OFFSET` moved (6.12) |
| `004-kbuild-symlink` | `nvidia.Kbuild`, `nvidia-modeset.Kbuild` | kbuild CWD symlink fix |

## Manual Build (without the script)

If you prefer to do it by hand:

```bash
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/470.256.02/NVIDIA-Linux-x86_64-470.256.02.run
sh NVIDIA-Linux-x86_64-470.256.02.run --extract-only
cd NVIDIA-Linux-x86_64-470.256.02
for p in ../001-*.patch ../002-*.patch ../003-*.patch ../004-*.patch; do patch -p1 < "$p"; done
cd kernel
make KERNEL_UNAME=$(uname -r) modules -j$(nproc)
sudo mkdir -p /lib/modules/$(uname -r)/extra
sudo cp *.ko /lib/modules/$(uname -r)/extra/
sudo depmod -a $(uname -r)
```

## Tested On

| Component | Version |
|-----------|---------|
| GPU | NVIDIA GeForce GTX 660 (GK106) |
| Driver | 470.256.02 |
| Kernel | 6.12.48+deb13 |
| Distro | LMDE 7 (gigi) / Debian Trixie |
| GCC | 14.x |

## Note: nvidia-settings

`nvidia-settings` is not included in the build script. If you want the NVIDIA Settings GUI:

```bash
sudo apt install nvidia-settings
```

It's version-independent, so the 550.x package from the repos works fine with our 470.256.02 kernel module.

## Known Limitations

- `os_lookup_user_io_memory()` (IO-memory PTE lookup) fails — only affects user-space IO mappings, not desktop/rendering
- `nvidia-drm.modeset=1` recommended as kernel parameter on 6.12+
- Will need re-patching for kernel updates (no DKMS auto-rebuild)

## Credits

- [joanbm/nvidia-470xx-linux-mainline](https://github.com/joanbm/nvidia-470xx-linux-mainline) — comprehensive patch collection
- Debian Salsa [nvidia-graphics-drivers](https://salsa.debian.org/nvidia-team/nvidia-graphics-drivers/-/commits/tesla-470/main) tesla-470 branch
- Joan Bruguera Micó — DRM 6.12 compat patches

## License

[MIT License](LICENSE) — use, fork, modify freely. NVIDIA's driver itself is proprietary; the patches and build script here are open.

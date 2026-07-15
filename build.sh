#!/usr/bin/env bash
#
# build.sh — Build NVIDIA 470.xx legacy driver with kernel 6.8+ patches
#
# Usage:
#   ./build.sh              Build kernel modules only
#   ./build.sh --install    Build and install everything
#   ./build.sh --deb        Build and package as .deb
#   ./build.sh --clean      Remove build artifacts
#   ./build.sh --help       Show this help
#
# Fork this script for other NVIDIA driver versions:
#   1. Change DRIVER_VERSION and DRIVER_URL below
#   2. Add/remove/rename .patch files in this directory
#   3. Update the PATCHES array to match

set -euo pipefail

# ─── Configuration (edit these when forking) ───────────────────────────────

DRIVER_VERSION="470.256.02"
DRIVER_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${DRIVER_VERSION}/NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
DRIVER_ARCHIVE="NVIDIA-Linux-x86_64-${DRIVER_VERSION}.run"
SOURCE_DIR="NVIDIA-Linux-x86_64-${DRIVER_VERSION}"

# Patches applied to kernel module source (in order)
PATCHES=(
    001-follow-pfn.patch
    002-conftest-gcc-flags.patch
    003-drm-compat.patch
    004-kbuild-symlink.patch
)

# ─── Colors ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
die()   { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }

# ─── Helpers ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_deps() {
    local missing=()
    for cmd in wget make gcc; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ! -d "/lib/modules/$(uname -r)/build" ]; then
        missing+=("kernel headers for $(uname -r)")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing dependencies: ${missing[*]}\n    Install them with:\n    sudo apt install build-essential linux-headers-\$(uname -r)"
    fi
}

download_source() {
    if [ -f "${SCRIPT_DIR}/${DRIVER_ARCHIVE}" ]; then
        info "Driver archive already downloaded"
        return
    fi
    info "Downloading NVIDIA ${DRIVER_VERSION} driver..."
    wget -q --show-progress -O "${SCRIPT_DIR}/${DRIVER_ARCHIVE}" "${DRIVER_URL}" \
        || die "Download failed. Check your internet connection."
    ok "Downloaded ${DRIVER_ARCHIVE}"
}

extract_source() {
    if [ -d "${SCRIPT_DIR}/${SOURCE_DIR}" ]; then
        info "Source already extracted"
        return
    fi
    info "Extracting driver source..."
    sh "${SCRIPT_DIR}/${DRIVER_ARCHIVE}" --extract-only --target "${SCRIPT_DIR}" \
        || die "Extraction failed"
    ok "Extracted to ${SOURCE_DIR}"
}

apply_patches() {
    info "Applying patches..."
    cd "${SCRIPT_DIR}/${SOURCE_DIR}"

    local applied=0
    for patch_name in "${PATCHES[@]}"; do
        local patch_path="${SCRIPT_DIR}/${patch_name}"
        if [ ! -f "$patch_path" ]; then
            die "Patch not found: ${patch_name}"
        fi
        if patch -p1 --dry-run < "$patch_path" &>/dev/null; then
            patch -p1 < "$patch_path"
            ok "Applied ${patch_name}"
            ((applied++))
        else
            warn "Patch ${patch_name} may have already been applied or doesn't fit, skipping"
        fi
    done

    cd "${SCRIPT_DIR}"
    ok "Applied ${applied}/${#PATCHES[@]} patches"
}

build_modules() {
    info "Building kernel modules..."
    cd "${SCRIPT_DIR}/${SOURCE_DIR}/kernel"

    make \
        KERNEL_UNAME="$(uname -r)" \
        modules \
        -j"$(nproc)" \
        IGNORE_CC_MISMATCH=1 \
        SYSSRC="/lib/modules/$(uname -r)/build" \
        LD="/usr/bin/ld.bfd" \
        NV_VERBOSE=1 \
        2>&1 | tail -20

    cd "${SCRIPT_DIR}"
    ok "Kernel modules built successfully"
}

install_modules() {
    [ "$(id -u)" -eq 0 ] || die "Install requires root. Run with sudo."

    local kmod_dir="/lib/modules/$(uname -r)/extra"
    info "Installing kernel modules to ${kmod_dir}..."
    mkdir -p "$kmod_dir"
    cp "${SCRIPT_DIR}/${SOURCE_DIR}/kernel/"*.ko "$kmod_dir/"
    depmod -a "$(uname -r)"
    ok "Kernel modules installed"
}

install_userspace() {
    [ "$(id -u)" -eq 0 ] || die "Install requires root. Run with sudo."
    local src="${SCRIPT_DIR}/${SOURCE_DIR}"

    info "Installing userspace binaries and libraries..."
    install -m 755 "${src}/nvidia-smi" /usr/bin/nvidia-smi

    local lib_dir="/usr/lib/x86_64-linux-gnu"
    mkdir -p "$lib_dir"
    cp "${src}"/lib*.so* "$lib_dir/"
    ldconfig
    ok "Userspace installed"
}

configure_system() {
    [ "$(id -u)" -eq 0 ] || die "Install requires root. Run with sudo."

    info "Configuring system..."

    # Blacklist nouveau
    cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    ok "Blacklisted nouveau"

    # Module autoloading
    cat > /etc/modules-load.d/nvidia.conf <<'EOF'
nvidia
nvidia-modeset
nvidia-drm
nvidia-uvm
EOF
    ok "Configured module autoloading"

    # Xorg config
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/20-nvidia.conf <<'EOF'
Section "OutputClass"
    Identifier "nvidia"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration"
    ModulePath "/usr/lib/x86_64-linux-gnu/nvidia/xorg,/usr/lib/xorg/modules"
EndSection
EOF
    ok "Xorg config installed"

    # Update initramfs
    if command -v update-initramfs &>/dev/null; then
        info "Updating initramfs..."
        update-initramfs -u
        ok "initramfs updated"
    else
        warn "update-initramfs not found, skipping initramfs update"
    fi
}

build_deb() {
    local pkg_name="nvidia-470xx-${DRIVER_VERSION}"
    local pkg_dir="${SCRIPT_DIR}/${pkg_name}"
    local src="${SCRIPT_DIR}/${SOURCE_DIR}"

    info "Building .deb package..."
    rm -rf "$pkg_dir"
    mkdir -p "${pkg_dir}/DEBIAN"
    mkdir -p "${pkg_dir}/usr/bin"
    mkdir -p "${pkg_dir}/usr/lib/x86_64-linux-gnu"
    mkdir -p "${pkg_dir}/lib/modules/$(uname -r)/extra"
    mkdir -p "${pkg_dir}/etc/modprobe.d"
    mkdir -p "${pkg_dir}/etc/modules-load.d"
    mkdir -p "${pkg_dir}/etc/X11/xorg.conf.d"

    # Control file
    cat > "${pkg_dir}/DEBIAN/control" <<EOF
Package: nvidia-470xx
Version: ${DRIVER_VERSION}
Section: non-free/x11
Priority: optional
Architecture: amd64
Depends: linux-headers-$(uname -r)
Maintainer: Peterplime <deoprgleebus@gmail.com>
Description: NVIDIA 470.xx legacy driver (patched for kernel 6.8+)
 Patches the NVIDIA 470.xx driver to build against Linux kernel 6.8+.
 Supports Kepler GPUs (GeForce 600/700 series).
 .
 Patches: follow_pfn, conftest GCC flags, DRM compat, kbuild symlink fix.
 Source: https://github.com/Peterplime/nvidia-470xx-kernel-6.12-patches
EOF

    # Binary files
    install -m 755 "${src}/nvidia-smi" "${pkg_dir}/usr/bin/nvidia-smi"
    cp "${src}"/lib*.so* "${pkg_dir}/usr/lib/x86_64-linux-gnu/"
    cp "${src}/kernel/"*.ko "${pkg_dir}/lib/modules/$(uname -r)/extra/"

    # Config files
    cat > "${pkg_dir}/etc/modprobe.d/blacklist-nouveau.conf" <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    cat > "${pkg_dir}/etc/modules-load.d/nvidia.conf" <<'EOF'
nvidia
nvidia-modeset
nvidia-drm
nvidia-uvm
EOF

    cat > "${pkg_dir}/etc/X11/xorg.conf.d/20-nvidia.conf" <<'EOF'
Section "OutputClass"
    Identifier "nvidia"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "AllowEmptyInitialConfiguration"
    ModulePath "/usr/lib/x86_64-linux-gnu/nvidia/xorg,/usr/lib/xorg/modules"
EndSection
EOF

    # Post-install script
    cat > "${pkg_dir}/DEBIAN/postinst" <<'POSTINST'
#!/bin/bash
set -e
depmod -a "$(uname -r)"
ldconfig
update-initramfs -u 2>/dev/null || true
echo ""
echo "NVIDIA 470.xx driver installed. Reboot to load."
echo "If using Wayland/X11, ensure 'nvidia-drm.modeset=1' is in your kernel params."
POSTINST
    chmod 755 "${pkg_dir}/DEBIAN/postinst"

    # Pre-removal script
    cat > "${pkg_dir}/DEBIAN/prerm" <<'PRERM'
#!/bin/bash
set -e
rm -f /lib/modules/*/extra/nvidia*.ko
depmod -a "$(uname -r)" 2>/dev/null || true
PRERM
    chmod 755 "${pkg_dir}/DEBIAN/prerm"

    # Build the .deb
    dpkg-deb --root-owner-group --build "$pkg_dir"

    local deb_path="${SCRIPT_DIR}/${pkg_name}_amd64.deb"
    if [ -f "$deb_path" ]; then
        ok "Package built: ${pkg_name}_amd64.deb"
        info "Install with: sudo dpkg -i ${pkg_name}_amd64.deb"
        info "Remove with:  sudo dpkg -r nvidia-470xx"
    else
        die "dpkg-deb failed"
    fi

    rm -rf "$pkg_dir"
}

clean_build() {
    info "Cleaning build artifacts..."
    rm -rf "${SCRIPT_DIR}/${SOURCE_DIR}"
    rm -f "${SCRIPT_DIR}/${pkg_name:-nvidia-470xx-*}_amd64.deb"
    ok "Cleaned"
}

show_help() {
    cat <<HELP
NVIDIA 470.xx Legacy Driver Builder (patched for kernel 6.8+)

Usage:
    $(basename "$0")              Build kernel modules only
    $(basename "$0") --install    Build + install modules, userspace, and config
    $(basename "$0") --deb        Build + package as .deb
    $(basename "$0") --clean      Remove downloaded source and build artifacts
    $(basename "$0") --help       Show this help

Forking for other driver versions:
    1. Edit DRIVER_VERSION and DRIVER_URL at the top of this script
    2. Add/remove/rename .patch files in this directory
    3. Update the PATCHES array to match your patches

What gets installed (--install / --deb):
    Kernel modules:  nvidia, nvidia-modeset, nvidia-drm, nvidia-uvm
    Userspace:       nvidia-smi, libnvidia-ml, libnvidia-glcore, etc.
    Config:          nouveau blacklist, module autoloading, Xorg OutputClass

Requirements:
    - Kernel headers for your running kernel
    - build-essential (gcc, make)
    - wget
    - dpkg-deb (for --deb only)

Tested on:
    LMDE 7 / Debian Trixie, kernel 6.12, GCC 14, GTX 660 (Kepler GK106)
HELP
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --clean)
            clean_build
            ;;
        --deb)
            check_deps
            download_source
            extract_source
            apply_patches
            build_modules
            install_modules
            build_deb
            ;;
        --install)
            check_deps
            download_source
            extract_source
            apply_patches
            build_modules
            install_modules
            install_userspace
            configure_system
            ok "Done! Reboot to load the NVIDIA driver."
            ;;
        "")
            check_deps
            download_source
            extract_source
            apply_patches
            build_modules
            ok "Build complete. Use --install or --deb to proceed."
            ;;
        *)
            die "Unknown option: $1\nRun '$(basename "$0") --help' for usage."
            ;;
    esac
}

main "$@"

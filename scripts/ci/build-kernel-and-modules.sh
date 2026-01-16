#!/bin/bash
# VyOS Custom Kernel + Driver Build Script
# This script runs inside the vyos-build Docker container
#
# Required environment variables:
#   KERNEL_VERSION - Kernel version (e.g., 6.6.117)
#   VYOS_VERSION   - VyOS version string
#   BUILD_TYPE     - Build type (generic, cloud-init)
#
# Optional environment variables:
#   CCACHE_DIR     - ccache directory (default: /ccache)
#   CCACHE_MAXSIZE - ccache max size (default: 5G)
#
# NOTE: All commands use sudo to avoid permission issues in Docker environment

set -euo pipefail

# =============================================
# Configuration
# =============================================
readonly WORK_DIR=/vyos/kernel-build
readonly CUSTOM_PKG_DIR=/vyos/custom-packages
readonly DEFCONFIG_PATH="/vyos/scripts/package-build/linux-kernel/arch/x86/configs/vyos_defconfig"

# Validate required environment variables
: "${KERNEL_VERSION:?KERNEL_VERSION is required}"
: "${VYOS_VERSION:?VYOS_VERSION is required}"
: "${BUILD_TYPE:?BUILD_TYPE is required}"

readonly KERNEL_DIR="${WORK_DIR}/linux-${KERNEL_VERSION}"
readonly KVER="${KERNEL_VERSION}-vyos"
MAJOR_VERSION=$(echo "$KERNEL_VERSION" | cut -d. -f1)
readonly MAJOR_VERSION

# Driver versions
readonly R8126_VERSION="10.016.00"
readonly R8126_URL="https://github.com/openwrt/rtl8126/releases/download/${R8126_VERSION}/r8126-${R8126_VERSION}.tar.bz2"

# =============================================
# Utility Functions
# =============================================

log_phase() {
    echo "============================================="
    echo "=== $1 ==="
    echo "============================================="
}

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Create deb package for kernel module
# Arguments:
#   $1 - pkg_name: Package name
#   $2 - pkg_version: Package version
#   $3 - module_file: Path to .ko file
#   $4 - module_dest_dir: Destination directory in package
#   $5 - description: Package description
#   $6 - depends: Depends field value (optional)
#   $7 - provides: Provides field value (optional)
#   $8 - conflicts: Conflicts field value (optional)
#   $9 - replaces: Replaces field value (optional)
create_module_deb() {
    local pkg_name=$1
    local pkg_version=$2
    local module_file=$3
    local module_dest_dir=$4
    local description=$5
    local depends=${6:-""}
    local provides=${7:-""}
    local conflicts=${8:-""}
    local replaces=${9:-""}

    local pkg_dir=/tmp/${pkg_name}-pkg
    sudo rm -rf "${pkg_dir}"
    sudo mkdir -p "${pkg_dir}/${module_dest_dir}"
    sudo mkdir -p "${pkg_dir}/DEBIAN"

    sudo cp "${module_file}" "${pkg_dir}/${module_dest_dir}/"

    # Write required fields first
    sudo tee "${pkg_dir}/DEBIAN/control" > /dev/null << CTRL
Package: ${pkg_name}
Version: ${pkg_version}
Section: kernel
Priority: optional
Architecture: amd64
CTRL

    # Append optional fields conditionally (avoids empty lines)
    if [ -n "$depends" ]; then
        echo "Depends: $depends" | sudo tee -a "${pkg_dir}/DEBIAN/control" > /dev/null
    fi
    if [ -n "$provides" ]; then
        echo "Provides: $provides" | sudo tee -a "${pkg_dir}/DEBIAN/control" > /dev/null
    fi
    if [ -n "$conflicts" ]; then
        echo "Conflicts: $conflicts" | sudo tee -a "${pkg_dir}/DEBIAN/control" > /dev/null
    fi
    if [ -n "$replaces" ]; then
        echo "Replaces: $replaces" | sudo tee -a "${pkg_dir}/DEBIAN/control" > /dev/null
    fi

    # Append final required fields
    sudo tee -a "${pkg_dir}/DEBIAN/control" > /dev/null << CTRL
Maintainer: github-actions@murata-lab.net
Description: ${description}
CTRL

    sudo tee "${pkg_dir}/DEBIAN/postinst" > /dev/null << POST
#!/bin/bash
depmod -a ${KVER} || true
POST
    sudo chmod 755 "${pkg_dir}/DEBIAN/postinst"

    sudo dpkg-deb --build "${pkg_dir}" "${CUSTOM_PKG_DIR}/${pkg_name}_${pkg_version}_amd64.deb"
}

# Sign kernel module
sign_module() {
    local module_file=$1

    sudo "${KERNEL_DIR}/scripts/sign-file" sha512 \
        "${KERNEL_DIR}/certs/signing_key.pem" \
        "${KERNEL_DIR}/certs/signing_key.pem" \
        "${module_file}"

    if sudo strings "${module_file}" | grep -q "~Module signature appended~"; then
        log_info "SUCCESS: $(basename "${module_file}") is signed"
    else
        log_error "$(basename "${module_file}") signature not detected"
        exit 1
    fi
}

# =============================================
# Phase 1: Build Custom Kernel
# =============================================
build_kernel() {
    log_phase "Phase 1: Build Custom Kernel"
    log_info "KERNEL_DIR: ${KERNEL_DIR}"
    log_info "KVER: ${KVER}"

    # Install build dependencies
    sudo apt-get update
    sudo apt-get install -y curl flex bison bc libssl-dev libelf-dev \
        libncurses-dev dwarves kmod cpio rsync debhelper fakeroot dpkg-dev ccache

    # Setup ccache
    export PATH="/usr/lib/ccache:$PATH"
    sudo ccache -s || true

    sudo mkdir -p "${WORK_DIR}" "${CUSTOM_PKG_DIR}"
    cd "${WORK_DIR}"

    # Download or use cached kernel source
    local kernel_tarball="linux-${KERNEL_VERSION}.tar.xz"
    if [ -f "/kernel-cache/${kernel_tarball}" ]; then
        log_info "Using cached kernel source..."
        sudo cp "/kernel-cache/${kernel_tarball}" .
    else
        log_info "Downloading kernel ${KERNEL_VERSION}..."
        sudo curl -L -O "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VERSION}.x/${kernel_tarball}"

        # Verify checksum
        log_info "Verifying kernel source checksum..."
        sudo curl -sL "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VERSION}.x/sha256sums.asc" -o sha256sums.asc || true
        if sudo grep -q "${kernel_tarball}" sha256sums.asc 2>/dev/null; then
            sudo grep "${kernel_tarball}" sha256sums.asc | sudo sha256sum -c - || {
                log_error "Kernel source checksum verification failed!"
                exit 1
            }
            log_info "Checksum verified successfully"
        else
            log_info "Checksum file not available, skipping verification"
        fi

        sudo cp "${kernel_tarball}" "/kernel-cache/" || true
    fi

    sudo tar xf "${kernel_tarball}"
    cd "linux-${KERNEL_VERSION}"

    # Apply VyOS defconfig
    if [ -f "${DEFCONFIG_PATH}" ]; then
        log_info "Using VyOS defconfig from scripts/package-build..."
        sudo cp "${DEFCONFIG_PATH}" .config
        sudo make olddefconfig
    else
        log_error "VyOS defconfig not found at ${DEFCONFIG_PATH}"
        sudo find /vyos -name "vyos_defconfig" -type f 2>/dev/null || true
        exit 1
    fi

    # Generate module signing keys
    log_info "Generating module signing keys..."
    sudo mkdir -p certs

    # x509.genkey content (base64 encoded)
    echo "W3JlcV0KZGVmYXVsdF9iaXRzID0gNDA5NgpkaXN0aW5ndWlzaGVkX25hbWUgPSByZXFfZGlzdGluZ3Vpc2hlZF9uYW1lCnByb21wdCA9IG5vCng1MDlfZXh0ZW5zaW9ucyA9IHYzX2NhCgpbcmVxX2Rpc3Rpbmd1aXNoZWRfbmFtZV0KQ04gPSBWeU9TIE1vZHVsZSBTaWduaW5nIEtleQplbWFpbEFkZHJlc3MgPSBidWlsZEB2eW9zLmxvY2FsCgpbdjNfY2FdCmJhc2ljQ29uc3RyYWludHM9Y3JpdGljYWwsQ0E6RkFMU0UKa2V5VXNhZ2U9ZGlnaXRhbFNpZ25hdHVyZQpzdWJqZWN0S2V5SWRlbnRpZmllcj1oYXNoCmF1dGhvcml0eUtleUlkZW50aWZpZXI9a2V5aWQK" | base64 -d | sudo tee x509.genkey > /dev/null

    sudo openssl req -new -nodes -utf8 -sha512 -days 36500 \
        -batch -x509 -config x509.genkey \
        -outform PEM -out certs/signing_key.pem \
        -keyout certs/signing_key.pem

    # Configure module signing
    sudo ./scripts/config --set-str MODULE_SIG_KEY "certs/signing_key.pem"
    sudo ./scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
    sudo ./scripts/config --enable MODULE_SIG_ALL
    sudo make olddefconfig

    # Verify MODULE_SIG settings
    log_info "Verifying MODULE_SIG settings..."
    sudo grep -E "MODULE_SIG|SYSTEM_TRUSTED" .config || true
    if ! sudo grep -q "CONFIG_MODULE_SIG=y" .config; then
        log_error "CONFIG_MODULE_SIG is not enabled!"
        exit 1
    fi
    if ! sudo grep -q "CONFIG_MODULE_SIG_ALL=y" .config; then
        log_error "CONFIG_MODULE_SIG_ALL is not enabled!"
        exit 1
    fi
    log_info "MODULE_SIG is properly configured."

    # Initialize git for deb-pkg
    sudo git init
    sudo git config user.email "build@vyos.local"
    sudo git config user.name "VyOS Kernel Builder"
    sudo git add -A
    sudo git commit -m "Initial commit for kernel build"

    # Disable debug info to speed up build
    sudo ./scripts/config --disable DEBUG_INFO
    sudo ./scripts/config --disable DEBUG_INFO_DWARF4
    sudo ./scripts/config --disable DEBUG_INFO_DWARF5
    sudo ./scripts/config --disable DEBUG_INFO_BTF

    # Disable unused drivers/features for router use case
    # NOTE: USB_SUPPORT must remain ENABLED for USB boot/installation
    sudo ./scripts/config --disable SOUND || true
    sudo ./scripts/config --disable MEDIA_SUPPORT || true
    sudo ./scripts/config --disable WIRELESS || true
    sudo ./scripts/config --disable CFG80211 || true
    sudo ./scripts/config --disable MAC80211 || true
    sudo ./scripts/config --disable DRM || true
    sudo ./scripts/config --disable STAGING || true

    # Enable Intel 10GbE driver (disabled in VyOS defconfig, required for X540-T2)
    # VyOS uses out-of-tree vyos-intel-ixgbe package, but it's signed with VyOS key
    # Building in-tree ensures the module is signed with our custom key
    sudo ./scripts/config --module IXGBE
    sudo ./scripts/config --module IXGBEVF

    sudo make olddefconfig

    # Build kernel
    log_info "Building kernel with $(nproc) cores..."
    sudo make -j"$(nproc)" CC="ccache gcc" deb-pkg LOCALVERSION=-vyos KDEB_PKGVERSION=1-1

    # Show ccache stats
    log_info "ccache stats:"
    sudo ccache -s || true

    # Save kernel packages
    sudo mv ../*.deb "${CUSTOM_PKG_DIR}/"

    # Save signing key for verification
    sudo openssl x509 -in "${KERNEL_DIR}/certs/signing_key.pem" -outform DER -out "${CUSTOM_PKG_DIR}/signing_key.x509"
    sudo cp "${KERNEL_DIR}/.config" "${CUSTOM_PKG_DIR}/kernel-config"

    log_info "Kernel packages:"
    sudo ls -la "${CUSTOM_PKG_DIR}/"
}

# =============================================
# Phase 2: Build and Sign r8126 Driver
# =============================================
build_r8126() {
    log_phase "Phase 2: Build and Sign r8126 Driver"

    cd /tmp
    sudo curl -L -o r8126.tar.bz2 "${R8126_URL}"
    sudo tar xjf r8126.tar.bz2
    cd "r8126-${R8126_VERSION}/src"

    log_info "Building r8126 module against ${KERNEL_DIR}..."
    sudo make -C "${KERNEL_DIR}" M="$(pwd)" modules

    sign_module r8126.ko
    sudo cp r8126.ko "${CUSTOM_PKG_DIR}/r8126-signed.ko"

    create_module_deb \
        "r8126-modules" \
        "${R8126_VERSION}-1" \
        "r8126.ko" \
        "lib/modules/${KVER}/kernel/drivers/net/ethernet/realtek" \
        "Realtek r8126 5GbE driver module (signed)" \
        "linux-image-${KVER}"

    log_info "Phase 2 completed"
}

# =============================================
# Phase 3: Build VyOS ISO
# =============================================
build_iso() {
    log_phase "Phase 3: Build VyOS ISO with Custom Kernel"

    cd /vyos

    # Copy custom packages to packages/ directory
    log_info "Copying custom packages to packages/ directory..."
    sudo mkdir -p /vyos/packages
    sudo cp "${CUSTOM_PKG_DIR}"/linux-image-*.deb /vyos/packages/
    sudo cp "${CUSTOM_PKG_DIR}"/linux-headers-*.deb /vyos/packages/ || true
    sudo cp "${CUSTOM_PKG_DIR}"/r8126-modules_*.deb /vyos/packages/

    log_info "Packages to be included in ISO:"
    sudo ls -la /vyos/packages/

    # Build ISO
    log_info "Building VyOS ISO with custom kernel..."
    sudo ./build-vyos-image \
        --architecture amd64 \
        --build-by "github-actions@murata-lab.net" \
        --build-comment "Custom ISO with r8126 driver (kernel ${KERNEL_VERSION})" \
        --version "${VYOS_VERSION}" \
        "${BUILD_TYPE}"

    log_info "Build completed"
    sudo ls -la /vyos/build/

    # Verify ISO contents
    log_info "Verifying ISO contents..."
    local iso_file
    iso_file=$(sudo find /vyos/build -maxdepth 1 -name "*.iso" -type f 2>/dev/null | head -1)
    if [ -n "${iso_file}" ]; then
        log_info "Checking ISO for custom kernel..."
        sudo mkdir -p /tmp/iso-check
        sudo mount -o loop "${iso_file}" /tmp/iso-check || true
        if [ -d "/tmp/iso-check/live" ]; then
            log_info "ISO mounted successfully"
            sudo ls -la /tmp/iso-check/live/ || true
        fi
        sudo umount /tmp/iso-check || true
    fi
}

# =============================================
# Main
# =============================================
main() {
    log_info "Starting VyOS Custom Build"
    log_info "Kernel Version: ${KERNEL_VERSION}"
    log_info "VyOS Version: ${VYOS_VERSION}"
    log_info "Build Type: ${BUILD_TYPE}"

    build_kernel
    build_r8126
    build_iso

    log_info "All phases completed successfully!"
}

main "$@"

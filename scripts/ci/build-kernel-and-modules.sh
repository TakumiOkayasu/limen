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
    # VyOS official repository provides vyos-intel-ixgbe package (out-of-tree, signed with VyOS key)
    # We build in-tree instead to ensure modules are signed with our custom kernel key
    # APT preferences (configured in build_iso()) block vyos-intel-* to prevent conflicts
    log_info "Enabling Intel IXGBE driver (required for X540-T2)..."
    sudo ./scripts/config --module IXGBE
    sudo ./scripts/config --module IXGBEVF

    sudo make olddefconfig

    # Verify IXGBE is enabled
    log_info "Verifying IXGBE driver configuration..."
    if sudo grep -q "CONFIG_IXGBE=m" .config; then
        log_info "SUCCESS: CONFIG_IXGBE=m is set"
    else
        log_error "CONFIG_IXGBE is not set to module! Current setting:"
        sudo grep "IXGBE" .config || echo "IXGBE not found in config"
        exit 1
    fi
    if sudo grep -q "CONFIG_IXGBEVF=m" .config; then
        log_info "SUCCESS: CONFIG_IXGBEVF=m is set"
    else
        log_error "CONFIG_IXGBEVF is not set to module! Current setting:"
        sudo grep "IXGBEVF" .config || echo "IXGBEVF not found in config"
        exit 1
    fi

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
# Phase 2.5: Create Driver Verification Package
# =============================================
build_driver_check_pkg() {
    log_phase "Phase 2.5: Create Driver Verification Package"

    local pkg_name="vyos-driver-check"
    local pkg_version="1.0.0"
    local pkg_dir="/tmp/${pkg_name}-pkg"

    sudo rm -rf "${pkg_dir}"
    sudo mkdir -p "${pkg_dir}/usr/local/bin"
    sudo mkdir -p "${pkg_dir}/etc/profile.d"
    sudo mkdir -p "${pkg_dir}/DEBIAN"

    # Copy driver-check script
    if [ -f "/vyos/scripts/ci/driver-check.sh" ]; then
        sudo cp /vyos/scripts/ci/driver-check.sh "${pkg_dir}/usr/local/bin/driver-check"
        sudo chmod 755 "${pkg_dir}/usr/local/bin/driver-check"
    else
        # Create inline if not available (for standalone builds)
        log_info "Creating driver-check script inline..."
        sudo tee "${pkg_dir}/usr/local/bin/driver-check" > /dev/null << 'SCRIPT'
#!/bin/bash
# VyOS Custom ISO - Driver Verification Script (inline version)
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== VyOS Driver Check ===${NC}"
echo ""

# Check kernel
echo -e "${BLUE}Kernel:${NC} $(uname -r)"

# Check ixgbe
echo ""
if modinfo ixgbe &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} ixgbe module available"
    if lsmod | grep -q "^ixgbe"; then
        echo -e "${GREEN}[OK]${NC} ixgbe module loaded"
    else
        echo -e "${BLUE}[INFO]${NC} ixgbe not loaded (no hardware?)"
    fi
else
    echo -e "${RED}[ERROR]${NC} ixgbe module NOT found!"
fi

# Check r8126
echo ""
if modinfo r8126 &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} r8126 module available"
    if lsmod | grep -q "^r8126"; then
        echo -e "${GREEN}[OK]${NC} r8126 module loaded"
    else
        echo -e "${BLUE}[INFO]${NC} r8126 not loaded (no hardware?)"
    fi
else
    echo -e "${RED}[ERROR]${NC} r8126 module NOT found!"
fi

# Show interfaces
echo ""
echo -e "${BLUE}Network interfaces:${NC}"
ip -br link show 2>/dev/null || ip link show
SCRIPT
        sudo chmod 755 "${pkg_dir}/usr/local/bin/driver-check"
    fi

    # Create profile.d script for login notification
    sudo tee "${pkg_dir}/etc/profile.d/driver-check-hint.sh" > /dev/null << 'PROFILE'
#!/bin/bash
# Hint for driver verification on custom VyOS ISO
if [ -x /usr/local/bin/driver-check ]; then
    echo ""
    echo "Custom VyOS ISO: Run 'driver-check' to verify network drivers"
    echo ""
fi
PROFILE
    sudo chmod 644 "${pkg_dir}/etc/profile.d/driver-check-hint.sh"

    # Create control file
    sudo tee "${pkg_dir}/DEBIAN/control" > /dev/null << CTRL
Package: ${pkg_name}
Version: ${pkg_version}
Section: utils
Priority: optional
Architecture: all
Maintainer: github-actions@murata-lab.net
Description: VyOS Custom ISO Driver Verification Tool
 Provides 'driver-check' command to verify that custom network
 drivers (ixgbe, r8126) are properly installed and working.
 Run 'driver-check' after USB live boot to verify drivers.
CTRL

    sudo dpkg-deb --build "${pkg_dir}" "${CUSTOM_PKG_DIR}/${pkg_name}_${pkg_version}_all.deb"
    log_info "Created ${pkg_name}_${pkg_version}_all.deb"
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
    sudo cp "${CUSTOM_PKG_DIR}"/vyos-driver-check_*.deb /vyos/packages/

    # Ensure proper permissions for packages directory
    sudo chmod -R 755 /vyos/packages
    sudo chown -R root:root /vyos/packages

    log_info "Packages to be included in ISO:"
    sudo ls -la /vyos/packages/

    # Generate package index for local repository
    log_info "Generating package index..."
    cd /vyos/packages
    sudo apt-ftparchive packages . | sudo tee Packages > /dev/null
    sudo gzip -c Packages | sudo tee Packages.gz > /dev/null
    sudo chmod 644 Packages Packages.gz
    cd /vyos

    # Prevent VyOS official Intel driver packages from overwriting custom kernel modules
    log_info "Configuring APT preferences to block vyos-intel-* packages..."
    sudo mkdir -p /vyos/data/live-build-config/includes.chroot/etc/apt/preferences.d
    sudo tee /vyos/data/live-build-config/includes.chroot/etc/apt/preferences.d/99-block-vyos-intel-drivers > /dev/null << 'EOF'
# Block VyOS official Intel driver packages to prevent overwriting custom kernel modules
# Custom kernel already includes IXGBE/IXGBEVF drivers signed with our key

Package: vyos-intel-ixgbe
Pin: release *
Pin-Priority: -1

Package: vyos-intel-ixgbevf
Pin: release *
Pin-Priority: -1

# Allow other vyos-intel packages (e.g., vyos-intel-qat) if needed
EOF
    sudo chmod 644 /vyos/data/live-build-config/includes.chroot/etc/apt/preferences.d/99-block-vyos-intel-drivers
    log_info "APT preferences configured to block: vyos-intel-ixgbe, vyos-intel-ixgbevf"

    # Install live-build hooks to remove vyos-intel-ixgbe modules from updates/
    # APT preferences only affects future installs, not packages already installed during build
    # The hook runs before squashfs generation and removes the conflicting modules
    log_info "Installing live-build hooks..."
    if [ -f /vyos/hooks/live/9999-remove-vyos-intel-ixgbe.chroot ]; then
        sudo mkdir -p /vyos/data/live-build-config/hooks/live
        sudo cp /vyos/hooks/live/9999-remove-vyos-intel-ixgbe.chroot \
            /vyos/data/live-build-config/hooks/live/
        sudo chmod 755 /vyos/data/live-build-config/hooks/live/9999-remove-vyos-intel-ixgbe.chroot
        log_info "Installed hook: 9999-remove-vyos-intel-ixgbe.chroot"
    else
        log_info "Hook file not found, skipping (vyos-intel-ixgbe may override custom ixgbe)"
    fi

    # Embed initial configuration and driver-check script
    log_info "Embedding initial configuration and driver-check..."
    if [ -f /vyos/build-script-embed-config.sh ]; then
        sudo /vyos/build-script-embed-config.sh
    else
        log_warn "embed-initial-config.sh not found, skipping initial config embedding"
    fi

    # Build ISO
    log_info "Building VyOS ISO with custom kernel..."
    sudo ./build-vyos-image \
        --architecture amd64 \
        --build-by "github-actions@murata-lab.net" \
        --build-comment "Custom ISO with IXGBE+r8126 drivers (kernel ${KERNEL_VERSION})" \
        --version "${VYOS_VERSION}" \
        "${BUILD_TYPE}"

    log_info "Build completed"
    sudo ls -la /vyos/build/

    # Verify ISO contents
    log_info "Verifying ISO contents..."
    local iso_file
    iso_file=$(sudo find /vyos/build -maxdepth 1 -name "*.iso" -type f 2>/dev/null | head -1)
    if [ -n "${iso_file}" ]; then
        log_info "Checking ISO for custom kernel and drivers..."
        sudo mkdir -p /tmp/iso-check
        sudo mount -o loop "${iso_file}" /tmp/iso-check || true
        if [ -d "/tmp/iso-check/live" ]; then
            log_info "ISO mounted successfully"
            sudo ls -la /tmp/iso-check/live/ || true

            # Extract and verify squashfs contents
            if [ -f "/tmp/iso-check/live/filesystem.squashfs" ]; then
                log_info "Extracting squashfs to verify drivers..."
                sudo mkdir -p /tmp/squashfs-check
                sudo unsquashfs -d /tmp/squashfs-check -f /tmp/iso-check/live/filesystem.squashfs \
                    "lib/modules/*/kernel/drivers/net/ethernet/intel/ixgbe/*" \
                    "lib/modules/*/kernel/drivers/net/ethernet/realtek/r8126*" 2>/dev/null || true

                # Check for IXGBE driver
                if sudo find /tmp/squashfs-check -name "ixgbe.ko*" 2>/dev/null | grep -q .; then
                    log_info "SUCCESS: IXGBE driver found in ISO"
                    sudo find /tmp/squashfs-check -name "ixgbe.ko*" -exec ls -la {} \;
                else
                    log_error "WARNING: IXGBE driver NOT found in ISO!"
                    log_info "Checking all available network drivers..."
                    sudo unsquashfs -l /tmp/iso-check/live/filesystem.squashfs 2>/dev/null | grep -E "ixgbe|intel" | head -20 || true
                fi

                # Check for r8126 driver
                if sudo find /tmp/squashfs-check -name "r8126.ko*" 2>/dev/null | grep -q .; then
                    log_info "SUCCESS: r8126 driver found in ISO"
                    sudo find /tmp/squashfs-check -name "r8126.ko*" -exec ls -la {} \;
                else
                    log_error "WARNING: r8126 driver NOT found in ISO!"
                fi

                # Verify APT preferences to block vyos-intel-* packages
                log_info "Checking APT preferences for vyos-intel package blocking..."
                if sudo find /tmp/squashfs-check -path "*/etc/apt/preferences.d/99-block-vyos-intel-drivers" 2>/dev/null | grep -q .; then
                    log_info "SUCCESS: APT preferences found in ISO"
                    sudo find /tmp/squashfs-check -path "*/etc/apt/preferences.d/99-block-vyos-intel-drivers" -exec cat {} \;
                else
                    log_error "WARNING: APT preferences NOT found in ISO!"
                fi

                sudo rm -rf /tmp/squashfs-check
            fi
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
    build_driver_check_pkg
    build_iso

    log_info "All phases completed successfully!"
}

main "$@"

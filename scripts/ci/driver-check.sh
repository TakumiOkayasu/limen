#!/bin/bash
# VyOS Custom ISO - Driver Verification Script
# This script verifies that required network drivers are present and working
#
# Usage:
#   driver-check          # Run full verification
#   driver-check --quiet  # Only show errors
#
# Exit codes:
#   0 - All drivers OK
#   1 - One or more drivers missing or not working

set -euo pipefail

# Colors for output (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

QUIET=${1:-}
ERRORS=0

log_info() {
    if [ "$QUIET" != "--quiet" ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_ok() {
    if [ "$QUIET" != "--quiet" ]; then
        echo -e "${GREEN}[OK]${NC} $1"
    fi
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ERRORS=$((ERRORS + 1))
}

print_header() {
    if [ "$QUIET" != "--quiet" ]; then
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}  VyOS Custom ISO - Driver Verification${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
    fi
}

# Check if a kernel module is loaded
check_module_loaded() {
    local module=$1
    if lsmod | grep -q "^${module}"; then
        return 0
    fi
    return 1
}

# Check if a kernel module exists (can be loaded)
check_module_exists() {
    local module=$1
    if modinfo "$module" &>/dev/null; then
        return 0
    fi
    return 1
}

# Check for PCI devices by vendor:device ID
check_pci_device() {
    local vendor_device=$1
    if lspci -nn 2>/dev/null | grep -qi "$vendor_device"; then
        return 0
    fi
    return 1
}

# Get network interfaces using a specific driver
get_interfaces_by_driver() {
    local driver=$1
    local interfaces=""
    for iface in /sys/class/net/*; do
        if [ -L "$iface/device/driver" ]; then
            local drv
            drv=$(basename "$(readlink "$iface/device/driver")")
            if [ "$drv" = "$driver" ]; then
                interfaces="$interfaces $(basename "$iface")"
            fi
        fi
    done
    echo "$interfaces"
}

# =============================================
# Driver Checks
# =============================================

check_ixgbe() {
    log_info "Checking Intel IXGBE driver (X540-T2)..."

    # Check if module exists
    if check_module_exists ixgbe; then
        log_ok "ixgbe module found in kernel"
    else
        log_error "ixgbe module NOT found in kernel!"
        return 1
    fi

    # Check if PCI device exists (Intel X540-T2: 8086:1528)
    if check_pci_device "8086:1528"; then
        log_ok "Intel X540-T2 PCI device detected"

        # Check if module is loaded
        if check_module_loaded ixgbe; then
            log_ok "ixgbe module is loaded"

            # Check for network interfaces
            local ifaces
            ifaces=$(get_interfaces_by_driver ixgbe)
            if [ -n "$ifaces" ]; then
                log_ok "Network interfaces using ixgbe:$ifaces"
            else
                log_warn "ixgbe loaded but no interfaces found (may need link)"
            fi
        else
            log_error "ixgbe module NOT loaded despite hardware present!"
            log_info "Try: sudo modprobe ixgbe"
            return 1
        fi
    else
        log_info "Intel X540-T2 hardware not detected (skipping load check)"
    fi

    return 0
}

check_r8126() {
    log_info "Checking Realtek r8126 driver (5GbE)..."

    # Check if module exists
    if check_module_exists r8126; then
        log_ok "r8126 module found in kernel"
    else
        log_error "r8126 module NOT found in kernel!"
        return 1
    fi

    # Check if PCI device exists (Realtek RTL8126: 10ec:8126)
    if check_pci_device "10ec:8126"; then
        log_ok "Realtek RTL8126 PCI device detected"

        # Check if module is loaded
        if check_module_loaded r8126; then
            log_ok "r8126 module is loaded"

            # Check for network interfaces
            local ifaces
            ifaces=$(get_interfaces_by_driver r8126)
            if [ -n "$ifaces" ]; then
                log_ok "Network interfaces using r8126:$ifaces"
            else
                log_warn "r8126 loaded but no interfaces found (may need link)"
            fi
        else
            log_error "r8126 module NOT loaded despite hardware present!"
            log_info "Try: sudo modprobe r8126"
            return 1
        fi
    else
        log_info "Realtek RTL8126 hardware not detected (skipping load check)"
    fi

    return 0
}

check_kernel_version() {
    log_info "Checking kernel version..."

    local kver
    kver=$(uname -r)
    log_ok "Running kernel: $kver"

    # Check if it's our custom kernel
    if echo "$kver" | grep -q "vyos"; then
        log_ok "Custom VyOS kernel detected"
    else
        log_warn "Not running custom VyOS kernel"
    fi
}

check_module_signatures() {
    log_info "Checking module signature enforcement..."

    if grep -q "CONFIG_MODULE_SIG_FORCE=y" /boot/config-"$(uname -r)" 2>/dev/null; then
        log_ok "MODULE_SIG_FORCE is enabled (signature required)"
    else
        log_warn "MODULE_SIG_FORCE is NOT enabled"
    fi

    if grep -q "CONFIG_MODULE_SIG=y" /boot/config-"$(uname -r)" 2>/dev/null; then
        log_ok "MODULE_SIG is enabled"
    else
        log_warn "MODULE_SIG is NOT enabled"
    fi
}

check_ssh_status() {
    log_info "Checking SSH service..."

    if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
        log_ok "SSH service is running"

        # Show listen addresses
        local ssh_ports
        ssh_ports=$(ss -tlnp 2>/dev/null | grep -E ':22\s' | awk '{print $4}' || true)
        if [ -n "$ssh_ports" ]; then
            log_ok "SSH listening on: $(echo "$ssh_ports" | tr '\n' ' ')"
        fi
    else
        log_warn "SSH service is NOT running"
    fi
}

check_network_config() {
    log_info "Checking network configuration..."

    # Check eth0 specifically
    if ip addr show eth0 >/dev/null 2>&1; then
        local eth0_addr
        eth0_addr=$(ip -4 addr show eth0 | grep inet | awk '{print $2}' | head -1 || true)
        if [ -n "$eth0_addr" ]; then
            log_ok "eth0 IP address: $eth0_addr"
        else
            log_warn "eth0 has no IPv4 address"
        fi

        local eth0_state
        eth0_state=$(ip -br link show eth0 | awk '{print $2}' || true)
        if [ "$eth0_state" = "UP" ]; then
            log_ok "eth0 is UP"
        else
            log_warn "eth0 is DOWN"
        fi
    else
        log_error "eth0 interface not found"
    fi
}

show_network_summary() {
    if [ "$QUIET" != "--quiet" ]; then
        echo ""
        log_info "Network interface summary:"
        echo ""
        ip -br link show 2>/dev/null || ip link show
        echo ""
    fi
}

# =============================================
# Main
# =============================================

main() {
    print_header

    check_kernel_version
    echo ""

    check_module_signatures
    echo ""

    check_network_config
    echo ""

    check_ssh_status
    echo ""

    check_ixgbe || true
    echo ""

    check_r8126 || true
    echo ""

    show_network_summary

    if [ $ERRORS -gt 0 ]; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  VERIFICATION FAILED: $ERRORS error(s)${NC}"
        echo -e "${RED}========================================${NC}"
        exit 1
    else
        if [ "$QUIET" != "--quiet" ]; then
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}  VERIFICATION PASSED: All drivers OK${NC}"
            echo -e "${GREEN}========================================${NC}"
        fi
        exit 0
    fi
}

main "$@"

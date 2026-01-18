#!/bin/bash
# Embed initial configuration and driver-check into VyOS ISO build
# This script runs inside the vyos-build Docker container

set -euo pipefail

readonly VYOS_DIR="/vyos"
readonly CHROOT_DIR="/vyos/build/live-build-config/includes.chroot"

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# =============================================
# Embed initial config.boot
# =============================================
embed_initial_config() {
    log_info "Embedding initial configuration..."

    local config_dest="${CHROOT_DIR}/opt/vyatta/etc/config/config.boot.default"

    sudo mkdir -p "$(dirname "$config_dest")"
    sudo cp "${VYOS_DIR}/initial-config.boot" "$config_dest"
    sudo chmod 644 "$config_dest"

    log_info "Initial config embedded: $config_dest"
}

# =============================================
# Embed driver-check script
# =============================================
embed_driver_check() {
    log_info "Embedding driver-check script..."

    local script_dest="${CHROOT_DIR}/usr/local/bin/driver-check"

    sudo mkdir -p "$(dirname "$script_dest")"
    sudo cp "${VYOS_DIR}/driver-check.sh" "$script_dest"
    sudo chmod 755 "$script_dest"

    log_info "driver-check embedded: $script_dest"
}

# =============================================
# Main
# =============================================
main() {
    log_info "Starting initial config embedding..."

    if [ ! -f "${VYOS_DIR}/initial-config.boot" ]; then
        log_error "initial-config.boot not found: ${VYOS_DIR}/initial-config.boot"
        exit 1
    fi

    if [ ! -f "${VYOS_DIR}/driver-check.sh" ]; then
        log_error "driver-check.sh not found: ${VYOS_DIR}/driver-check.sh"
        exit 1
    fi

    embed_initial_config
    embed_driver_check

    log_info "Initial config embedding completed successfully"
}

main "$@"

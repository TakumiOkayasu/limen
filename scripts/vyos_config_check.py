#!/usr/bin/env python3
"""VyOS configuration checker script.

This script connects to VyOS via SSH and validates the configuration
against expected settings defined in CLAUDE.md.

Usage:
    # Check all configurations
    python vyos_config_check.py

    # Check specific category
    python vyos_config_check.py --category interface

    # Use custom SSH settings
    python vyos_config_check.py --host 192.168.1.1 --user vyos

Categories:
    interface  - Network interface settings (eth0, eth1, eth2, wg0)
    ipv6       - IPv6 settings (RA, DHCPv6-PD)
    firewall   - Firewall rules
    wireguard  - WireGuard VPN settings
    ddns       - Dynamic DNS settings
    routing    - Routing and NAT settings
    all        - All categories (default)
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable


@dataclass
class CheckResult:
    """Result of a configuration check."""

    name: str
    passed: bool
    message: str
    details: str = ""


@dataclass
class ConfigCheck:
    """Configuration check definition."""

    name: str
    command: str
    validator: Callable[[str], CheckResult]
    category: str


def run_vyos_command(
    host: str, user: str, command: str, key_file: str | None = None
) -> tuple[int, str, str]:
    """Run a command on VyOS via SSH.

    Args:
        host: VyOS hostname or IP
        user: SSH username
        command: VyOS operational command
        key_file: Optional SSH key file path

    Returns:
        Tuple of (return_code, stdout, stderr)
    """
    ssh_cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes"]
    if key_file:
        ssh_cmd.extend(["-i", key_file])
    ssh_cmd.extend([f"{user}@{host}", command])

    try:
        result = subprocess.run(
            ssh_cmd, capture_output=True, text=True, timeout=30  # noqa: S603
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "SSH command timed out"
    except FileNotFoundError:
        return 1, "", "SSH client not found"


def check_interface_eth0(output: str) -> CheckResult:
    """Check eth0 (WXR connection) configuration."""
    checks = [
        ("192.168.100.2/24" in output, "IPv4 address 192.168.100.2/24"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult(
            "eth0 (WXR接続)", False, f"Missing: {', '.join(failed)}", output
        )
    return CheckResult("eth0 (WXR接続)", True, "✅ 192.168.100.2/24 configured")


def check_interface_eth1(output: str) -> CheckResult:
    """Check eth1 (WAN) configuration."""
    checks = [
        ("dhcpv6" in output.lower() or "2404:" in output, "DHCPv6-PD enabled"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult("eth1 (WAN)", False, f"Missing: {', '.join(failed)}", output)
    return CheckResult("eth1 (WAN)", True, "✅ DHCPv6-PD configured")


def check_interface_eth2(output: str) -> CheckResult:
    """Check eth2 (LAN) configuration."""
    checks = [
        ("192.168.1.1" in output, "IPv4 address 192.168.1.1"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult("eth2 (LAN)", False, f"Missing: {', '.join(failed)}", output)
    return CheckResult("eth2 (LAN)", True, "✅ 192.168.1.1 configured")


def check_interface_wg0(output: str) -> CheckResult:
    """Check wg0 (WireGuard) configuration."""
    checks = [
        ("10.10.10.1" in output, "IPv4 address 10.10.10.1"),
        ("fd00:10:10:10::1" in output, "IPv6 address fd00:10:10:10::1"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult(
            "wg0 (WireGuard)", False, f"Missing: {', '.join(failed)}", output
        )
    return CheckResult("wg0 (WireGuard)", True, "✅ 10.10.10.1, fd00:10:10:10::1")


def check_ipv6_ra(output: str) -> CheckResult:
    """Check IPv6 Router Advertisement configuration."""
    if "eth2" not in output:
        return CheckResult("IPv6 RA", False, "RA not configured on eth2", output)
    return CheckResult("IPv6 RA", True, "✅ RA configured on eth2")


def check_dhcpv6_pd(output: str) -> CheckResult:
    """Check DHCPv6-PD configuration."""
    checks = [
        ("eth1" in output, "DHCPv6-PD on eth1"),
        ("duid" in output.lower() or "pd" in output.lower(), "DUID/PD configured"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult(
            "DHCPv6-PD", False, f"Missing: {', '.join(failed)}", output
        )
    return CheckResult("DHCPv6-PD", True, "✅ DHCPv6-PD on eth1")


def check_firewall_input(output: str) -> CheckResult:
    """Check input firewall rules."""
    if "input" not in output.lower():
        return CheckResult("FW Input", False, "Input filter not configured", output)
    return CheckResult("FW Input", True, "✅ Input filter configured")


def check_firewall_forward(output: str) -> CheckResult:
    """Check forward firewall rules."""
    if "forward" not in output.lower():
        return CheckResult("FW Forward", False, "Forward filter not configured", output)
    return CheckResult("FW Forward", True, "✅ Forward filter configured")


def check_wireguard_interface(output: str) -> CheckResult:
    """Check WireGuard interface configuration."""
    checks = [
        ("wg0" in output, "wg0 interface"),
        ("51820" in output, "Port 51820"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult(
            "WireGuard", False, f"Missing: {', '.join(failed)}", output
        )
    return CheckResult("WireGuard", True, "✅ wg0 on port 51820")


def check_wireguard_peers(output: str) -> CheckResult:
    """Check WireGuard peer configuration."""
    peer_count = output.lower().count("peer")
    if peer_count < 2:
        return CheckResult(
            "WG Peers", False, f"Expected 2 peers, found {peer_count}", output
        )
    return CheckResult("WG Peers", True, f"✅ {peer_count} peers configured")


def check_ddns(output: str) -> CheckResult:
    """Check Dynamic DNS configuration."""
    checks = [
        ("cloudflare" in output.lower(), "Cloudflare provider"),
        ("router.murata-lab.net" in output or "murata-lab" in output, "Domain"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult("DDNS", False, f"Missing: {', '.join(failed)}", output)
    return CheckResult("DDNS", True, "✅ Cloudflare DDNS configured")


def check_default_route(output: str) -> CheckResult:
    """Check default route configuration."""
    if "192.168.100.1" not in output:
        return CheckResult(
            "Default Route", False, "Default route via 192.168.100.1 not found", output
        )
    return CheckResult("Default Route", True, "✅ via 192.168.100.1 (WXR)")


def check_nat_source(output: str) -> CheckResult:
    """Check NAT source rules."""
    checks = [
        ("masquerade" in output.lower() or "source" in output.lower(), "Source NAT"),
    ]
    failed = [msg for passed, msg in checks if not passed]
    if failed:
        return CheckResult("NAT Source", False, f"Missing: {', '.join(failed)}", output)
    return CheckResult("NAT Source", True, "✅ Source NAT configured")


# Define all checks
CONFIG_CHECKS: list[ConfigCheck] = [
    # Interface checks
    ConfigCheck("eth0", "show interfaces ethernet eth0", check_interface_eth0, "interface"),
    ConfigCheck("eth1", "show interfaces ethernet eth1", check_interface_eth1, "interface"),
    ConfigCheck("eth2", "show interfaces ethernet eth2", check_interface_eth2, "interface"),
    ConfigCheck("wg0", "show interfaces wireguard wg0", check_interface_wg0, "interface"),
    # IPv6 checks
    ConfigCheck("RA", "show configuration commands | grep router-advert", check_ipv6_ra, "ipv6"),
    ConfigCheck("DHCPv6-PD", "show configuration commands | grep dhcpv6", check_dhcpv6_pd, "ipv6"),
    # Firewall checks
    ConfigCheck("FW Input", "show configuration commands | grep 'firewall.*input'", check_firewall_input, "firewall"),
    ConfigCheck("FW Forward", "show configuration commands | grep 'firewall.*forward'", check_firewall_forward, "firewall"),
    # WireGuard checks
    ConfigCheck("WG Interface", "show configuration commands | grep wireguard", check_wireguard_interface, "wireguard"),
    ConfigCheck("WG Peers", "show configuration commands | grep 'wireguard.*peer'", check_wireguard_peers, "wireguard"),
    # DDNS checks
    ConfigCheck("DDNS", "show configuration commands | grep dynamic-dns", check_ddns, "ddns"),
    # Routing checks
    ConfigCheck("Default Route", "show ip route 0.0.0.0/0", check_default_route, "routing"),
    ConfigCheck("NAT Source", "show configuration commands | grep 'nat source'", check_nat_source, "routing"),
]


def run_checks(
    host: str,
    user: str,
    key_file: str | None,
    category: str,
    verbose: bool,
) -> list[CheckResult]:
    """Run configuration checks.

    Args:
        host: VyOS hostname or IP
        user: SSH username
        key_file: Optional SSH key file path
        category: Category to check ('all' for all)
        verbose: Show detailed output

    Returns:
        List of check results
    """
    results: list[CheckResult] = []
    checks = [c for c in CONFIG_CHECKS if category == "all" or c.category == category]

    for check in checks:
        if verbose:
            print(f"Checking {check.name}...", file=sys.stderr)

        returncode, stdout, stderr = run_vyos_command(host, user, check.command, key_file)

        if returncode != 0 and not stdout:
            result = CheckResult(
                check.name,
                False,
                f"Command failed: {stderr or 'Unknown error'}",
            )
        else:
            result = check.validator(stdout)

        results.append(result)

    return results


def print_results(results: list[CheckResult], verbose: bool) -> int:
    """Print check results.

    Args:
        results: List of check results
        verbose: Show detailed output

    Returns:
        Exit code (0 if all passed, 1 otherwise)
    """
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed

    print("\n" + "=" * 50)
    print("VyOS Configuration Check Results")
    print("=" * 50)

    # Group by status
    print("\n✅ PASSED:")
    for r in results:
        if r.passed:
            print(f"  {r.name}: {r.message}")

    if failed > 0:
        print("\n❌ FAILED:")
        for r in results:
            if not r.passed:
                print(f"  {r.name}: {r.message}")
                if verbose and r.details:
                    for line in r.details.split("\n")[:5]:
                        print(f"    | {line}")

    print("\n" + "-" * 50)
    print(f"Summary: {passed}/{len(results)} checks passed")

    if failed > 0:
        print(f"⚠️  {failed} check(s) failed")
        return 1

    print("✅ All checks passed")
    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Check VyOS configuration against expected settings"
    )
    parser.add_argument(
        "--host",
        default="192.168.1.1",
        help="VyOS hostname or IP (default: 192.168.1.1)",
    )
    parser.add_argument(
        "--user",
        default="vyos",
        help="SSH username (default: vyos)",
    )
    parser.add_argument(
        "--key-file",
        "-i",
        help="SSH private key file",
    )
    parser.add_argument(
        "--category",
        "-c",
        choices=["interface", "ipv6", "firewall", "wireguard", "ddns", "routing", "all"],
        default="all",
        help="Category to check (default: all)",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show detailed output",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show commands without executing",
    )

    args = parser.parse_args()

    if args.dry_run:
        print("Commands that would be executed:")
        checks = [c for c in CONFIG_CHECKS if args.category == "all" or c.category == args.category]
        for check in checks:
            print(f"  [{check.category}] {check.name}: {check.command}")
        return 0

    print(f"Connecting to {args.user}@{args.host}...")
    results = run_checks(args.host, args.user, args.key_file, args.category, args.verbose)
    return print_results(results, args.verbose)


if __name__ == "__main__":
    sys.exit(main())

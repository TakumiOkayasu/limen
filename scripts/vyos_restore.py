#!/usr/bin/env python3
"""VyOS configuration restore script.

This script generates VyOS configuration commands from a backup file,
replacing placeholders with actual secret values from environment variables
or an .env file.

Usage:
    # Generate restore commands (dry-run, prints to stdout)
    python vyos_restore.py

    # Generate restore commands with custom env file
    python vyos_restore.py --env-file /path/to/.env

    # Output to file
    python vyos_restore.py --output restore-commands.txt

Required environment variables (or .env file):
    VYOS_SSH_PUBKEY            - SSH public key (ed25519)
    VYOS_WG_PRIVATE_KEY        - WireGuard server private key
    VYOS_WG_MAC_PUBKEY         - WireGuard Mac client public key
    VYOS_WG_IPHONE_PUBKEY      - WireGuard iPhone client public key
    VYOS_CF_ACCOUNT_API_TOKEN  - Cloudflare Account API token for DDNS (NOT user token)
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO


@dataclass
class SecretMapping:
    """Mapping between placeholder pattern and environment variable."""

    pattern: str
    env_var: str
    description: str


# Define secret mappings
SECRET_MAPPINGS = [
    SecretMapping(
        pattern=r"<公開鍵>",
        env_var="VYOS_SSH_PUBKEY",
        description="SSH public key (ed25519)",
    ),
    SecretMapping(
        pattern=r"<VyOS秘密鍵>",
        env_var="VYOS_WG_PRIVATE_KEY",
        description="WireGuard server private key",
    ),
    SecretMapping(
        pattern=r"<Mac公開鍵>",
        env_var="VYOS_WG_MAC_PUBKEY",
        description="WireGuard Mac client public key",
    ),
    SecretMapping(
        pattern=r"<iPhone公開鍵>",
        env_var="VYOS_WG_IPHONE_PUBKEY",
        description="WireGuard iPhone client public key",
    ),
    SecretMapping(
        pattern=r"<Cloudflare APIトークン>",
        env_var="VYOS_CF_ACCOUNT_API_TOKEN",
        description="Cloudflare Account API token for DDNS (NOT user token)",
    ),
]


def load_env_file(env_path: Path) -> dict[str, str]:
    """Load environment variables from a .env file.

    Args:
        env_path: Path to the .env file

    Returns:
        Dictionary of environment variables
    """
    env_vars: dict[str, str] = {}

    if not env_path.exists():
        return env_vars

    with open(env_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if not line or line.startswith("#"):
                continue
            # Parse KEY=VALUE (handle quoted values)
            if "=" in line:
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()
                # Remove surrounding quotes if present
                if (value.startswith('"') and value.endswith('"')) or (
                    value.startswith("'") and value.endswith("'")
                ):
                    value = value[1:-1]
                env_vars[key] = value

    return env_vars


def get_secret_value(env_var: str, env_vars: dict[str, str]) -> str | None:
    """Get secret value from environment or loaded env file.

    Args:
        env_var: Environment variable name
        env_vars: Dictionary of loaded environment variables

    Returns:
        The secret value or None if not found
    """
    # Check loaded env file first, then system environment
    return env_vars.get(env_var) or os.environ.get(env_var)


def check_missing_secrets(env_vars: dict[str, str]) -> list[SecretMapping]:
    """Check for missing required secrets.

    Args:
        env_vars: Dictionary of loaded environment variables

    Returns:
        List of missing secret mappings
    """
    missing = []
    for mapping in SECRET_MAPPINGS:
        if not get_secret_value(mapping.env_var, env_vars):
            missing.append(mapping)
    return missing


def parse_backup_file(backup_path: Path) -> list[str]:
    """Parse backup file and extract VyOS set commands.

    Args:
        backup_path: Path to the backup file

    Returns:
        List of VyOS set commands (including commented ones)
    """
    commands: list[str] = []

    with open(backup_path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip()

            # Skip empty lines and pure comment lines (not commented commands)
            if not line:
                continue

            # Handle commented set commands (lines like "# set ...")
            if line.startswith("# set "):
                # This is a commented command with placeholder - keep it
                commands.append(line)
                continue

            # Skip other comments
            if line.startswith("#"):
                continue

            # Regular set commands
            if line.startswith("set "):
                commands.append(line)

    return commands


def replace_placeholders(
    commands: list[str], env_vars: dict[str, str]
) -> tuple[list[str], list[str]]:
    """Replace placeholders with actual secret values.

    Args:
        commands: List of VyOS commands
        env_vars: Dictionary of environment variables

    Returns:
        Tuple of (processed commands, warnings)
    """
    processed: list[str] = []
    warnings: list[str] = []

    for cmd in commands:
        original_cmd = cmd
        is_commented = cmd.startswith("# ")

        # Remove comment prefix for processing
        if is_commented:
            cmd = cmd[2:]

        # Check each secret mapping
        for mapping in SECRET_MAPPINGS:
            if mapping.pattern in cmd:
                value = get_secret_value(mapping.env_var, env_vars)
                if value:
                    cmd = cmd.replace(mapping.pattern, value)
                else:
                    warnings.append(
                        f"Missing {mapping.env_var} for placeholder {mapping.pattern}"
                    )
                    # Keep original (commented) if secret not available
                    cmd = original_cmd
                    break

        # Only add command if it was successfully processed
        # (either no placeholders or all replaced)
        if cmd != original_cmd or not is_commented:
            processed.append(cmd)

    return processed, warnings


def generate_restore_script(
    commands: list[str], output: TextIO, include_header: bool = True
) -> None:
    """Generate VyOS restore script.

    Args:
        commands: List of VyOS set commands
        output: Output file handle
        include_header: Whether to include header comments
    """
    if include_header:
        output.write("# VyOS Configuration Restore Commands\n")
        output.write("# Generated by vyos_restore.py\n")
        output.write("#\n")
        output.write("# Usage:\n")
        output.write("#   1. Login to VyOS\n")
        output.write("#   2. Enter configuration mode: configure\n")
        output.write("#   3. Paste these commands\n")
        output.write("#   4. Commit and save: commit; save\n")
        output.write("#\n")
        output.write("# Or run directly:\n")
        output.write(
            "#   vbash -c 'source /opt/vyatta/etc/functions/script-template'\n"
        )
        output.write("#   configure\n")
        output.write("#   <paste commands>\n")
        output.write("#   commit\n")
        output.write("#   save\n")
        output.write("#\n\n")

    for cmd in commands:
        output.write(f"{cmd}\n")


def main() -> int:
    """Main entry point.

    Returns:
        Exit code (0 for success, non-zero for errors)
    """
    parser = argparse.ArgumentParser(
        description="Generate VyOS restore commands from backup file"
    )
    parser.add_argument(
        "--backup",
        type=Path,
        default=Path(__file__).parent / "vyos-config-template.txt",
        help="Path to backup file (default: vyos-config-template.txt)",
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=Path(__file__).parent / "vyos-restore.env",
        help="Path to .env file with secrets (default: vyos-restore.env)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Output file (default: stdout)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Only check for missing secrets, don't generate output",
    )
    parser.add_argument(
        "--no-header",
        action="store_true",
        help="Don't include header comments in output",
    )

    args = parser.parse_args()

    # Load env file
    env_vars = load_env_file(args.env_file)

    # Check for missing secrets
    if args.check:
        missing = check_missing_secrets(env_vars)
        if missing:
            print("Missing secrets:", file=sys.stderr)
            for m in missing:
                print(f"  {m.env_var}: {m.description}", file=sys.stderr)
            return 1
        print("All secrets are configured.", file=sys.stderr)
        return 0

    # Check backup file exists
    if not args.backup.exists():
        print(f"Error: Backup file not found: {args.backup}", file=sys.stderr)
        return 1

    # Parse backup file
    commands = parse_backup_file(args.backup)
    if not commands:
        print("Error: No commands found in backup file", file=sys.stderr)
        return 1

    # Replace placeholders
    processed, warnings = replace_placeholders(commands, env_vars)

    # Print warnings
    for warning in warnings:
        print(f"Warning: {warning}", file=sys.stderr)

    # Generate output
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            generate_restore_script(processed, f, include_header=not args.no_header)
        print(f"Restore commands written to: {args.output}", file=sys.stderr)
    else:
        generate_restore_script(
            processed, sys.stdout, include_header=not args.no_header
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())

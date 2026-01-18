"""Tests for VyOS restore script."""

from __future__ import annotations

import sys
from io import StringIO
from pathlib import Path
from textwrap import dedent
from typing import TYPE_CHECKING
from unittest.mock import patch

import pytest

# Add secrets/scripts to path for import
sys.path.insert(0, str(Path(__file__).parent.parent / "secrets" / "scripts"))

from vyos_restore import (
    SECRET_MAPPINGS,
    SecretMapping,
    check_missing_secrets,
    generate_restore_script,
    get_secret_value,
    load_env_file,
    parse_backup_file,
    replace_placeholders,
)

if TYPE_CHECKING:
    pass


class TestLoadEnvFile:
    """Tests for load_env_file function."""

    def test_load_simple_env(self, tmp_path: Path) -> None:
        """Test loading simple KEY=VALUE pairs."""
        env_file = tmp_path / ".env"
        env_file.write_text("FOO=bar\nBAZ=qux\n")

        result = load_env_file(env_file)

        assert result == {"FOO": "bar", "BAZ": "qux"}

    def test_load_quoted_values(self, tmp_path: Path) -> None:
        """Test loading values with quotes."""
        env_file = tmp_path / ".env"
        env_file.write_text('DOUBLE="hello world"\nSINGLE=\'foo bar\'\n')

        result = load_env_file(env_file)

        assert result == {"DOUBLE": "hello world", "SINGLE": "foo bar"}

    def test_skip_comments(self, tmp_path: Path) -> None:
        """Test that comments are skipped."""
        env_file = tmp_path / ".env"
        env_file.write_text("# This is a comment\nKEY=value\n# Another comment\n")

        result = load_env_file(env_file)

        assert result == {"KEY": "value"}

    def test_skip_empty_lines(self, tmp_path: Path) -> None:
        """Test that empty lines are skipped."""
        env_file = tmp_path / ".env"
        env_file.write_text("KEY1=value1\n\n\nKEY2=value2\n")

        result = load_env_file(env_file)

        assert result == {"KEY1": "value1", "KEY2": "value2"}

    def test_missing_file_returns_empty(self, tmp_path: Path) -> None:
        """Test that missing file returns empty dict."""
        env_file = tmp_path / "nonexistent.env"

        result = load_env_file(env_file)

        assert result == {}

    def test_value_with_equals_sign(self, tmp_path: Path) -> None:
        """Test value containing equals sign."""
        env_file = tmp_path / ".env"
        env_file.write_text("KEY=value=with=equals\n")

        result = load_env_file(env_file)

        assert result == {"KEY": "value=with=equals"}


class TestGetSecretValue:
    """Tests for get_secret_value function."""

    def test_get_from_env_vars_dict(self) -> None:
        """Test getting value from env_vars dict."""
        env_vars = {"MY_KEY": "my_value"}

        result = get_secret_value("MY_KEY", env_vars)

        assert result == "my_value"

    def test_get_from_system_env(self) -> None:
        """Test getting value from system environment."""
        with patch.dict("os.environ", {"SYSTEM_KEY": "system_value"}):
            result = get_secret_value("SYSTEM_KEY", {})

        assert result == "system_value"

    def test_env_vars_takes_precedence(self) -> None:
        """Test that env_vars dict takes precedence over system env."""
        env_vars = {"KEY": "from_dict"}
        with patch.dict("os.environ", {"KEY": "from_system"}):
            result = get_secret_value("KEY", env_vars)

        assert result == "from_dict"

    def test_missing_key_returns_none(self) -> None:
        """Test that missing key returns None."""
        result = get_secret_value("NONEXISTENT", {})

        assert result is None


class TestCheckMissingSecrets:
    """Tests for check_missing_secrets function."""

    def test_all_secrets_present(self) -> None:
        """Test when all required secrets are present."""
        env_vars = {mapping.env_var: "some_value" for mapping in SECRET_MAPPINGS}

        result = check_missing_secrets(env_vars)

        assert result == []

    def test_some_secrets_missing(self) -> None:
        """Test when some secrets are missing."""
        env_vars = {SECRET_MAPPINGS[0].env_var: "value"}

        result = check_missing_secrets(env_vars)

        assert len(result) == len(SECRET_MAPPINGS) - 1

    def test_all_secrets_missing(self) -> None:
        """Test when all secrets are missing."""
        result = check_missing_secrets({})

        assert len(result) == len(SECRET_MAPPINGS)


class TestParseBackupFile:
    """Tests for parse_backup_file function."""

    def test_parse_set_commands(self, tmp_path: Path) -> None:
        """Test parsing regular set commands."""
        backup = tmp_path / "backup.txt"
        backup.write_text(
            dedent("""
            set system host-name 'router'
            set interfaces ethernet eth0 address '192.168.1.1/24'
        """).strip()
        )

        result = parse_backup_file(backup)

        assert result == [
            "set system host-name 'router'",
            "set interfaces ethernet eth0 address '192.168.1.1/24'",
        ]

    def test_parse_commented_set_commands(self, tmp_path: Path) -> None:
        """Test parsing commented set commands (with placeholders)."""
        backup = tmp_path / "backup.txt"
        backup.write_text(
            dedent("""
            set system host-name 'router'
            # set interfaces wireguard wg0 private-key '<VyOS秘密鍵>'
        """).strip()
        )

        result = parse_backup_file(backup)

        assert len(result) == 2
        assert result[1] == "# set interfaces wireguard wg0 private-key '<VyOS秘密鍵>'"

    def test_skip_pure_comments(self, tmp_path: Path) -> None:
        """Test that pure comments (not commands) are skipped."""
        backup = tmp_path / "backup.txt"
        backup.write_text(
            dedent("""
            # This is a comment
            # --- Section header ---
            set system host-name 'router'
        """).strip()
        )

        result = parse_backup_file(backup)

        assert result == ["set system host-name 'router'"]

    def test_skip_empty_lines(self, tmp_path: Path) -> None:
        """Test that empty lines are skipped."""
        backup = tmp_path / "backup.txt"
        backup.write_text("set foo\n\n\nset bar\n")

        result = parse_backup_file(backup)

        assert result == ["set foo", "set bar"]


class TestReplacePlaceholders:
    """Tests for replace_placeholders function."""

    def test_replace_all_placeholders(self) -> None:
        """Test replacing all placeholders with values."""
        commands = [
            "# set interfaces wireguard wg0 private-key '<VyOS秘密鍵>'",
            "# set interfaces wireguard wg0 peer mac public-key '<Mac公開鍵>'",
        ]
        env_vars = {
            "VYOS_WG_PRIVATE_KEY": "server_private_key",
            "VYOS_WG_MAC_PUBKEY": "mac_public_key",
        }

        result, warnings = replace_placeholders(commands, env_vars)

        assert (
            "set interfaces wireguard wg0 private-key 'server_private_key'" in result
        )
        assert (
            "set interfaces wireguard wg0 peer mac public-key 'mac_public_key'" in result
        )
        assert warnings == []

    def test_missing_secret_generates_warning(self) -> None:
        """Test that missing secrets generate warnings."""
        commands = ["# set service dns dynamic name cloudflare password '<Cloudflare APIトークン>'"]
        env_vars: dict[str, str] = {}

        result, warnings = replace_placeholders(commands, env_vars)

        assert len(warnings) == 1
        assert "VYOS_CF_API_TOKEN" in warnings[0]

    def test_regular_commands_pass_through(self) -> None:
        """Test that regular commands without placeholders pass through."""
        commands = [
            "set system host-name 'router'",
            "set interfaces ethernet eth0 address '192.168.1.1/24'",
        ]

        result, warnings = replace_placeholders(commands, {})

        assert result == commands
        assert warnings == []


class TestGenerateRestoreScript:
    """Tests for generate_restore_script function."""

    def test_generate_with_header(self) -> None:
        """Test generating script with header."""
        commands = ["set system host-name 'router'"]
        output = StringIO()

        generate_restore_script(commands, output, include_header=True)

        result = output.getvalue()
        assert "# VyOS Configuration Restore Commands" in result
        assert "set system host-name 'router'" in result

    def test_generate_without_header(self) -> None:
        """Test generating script without header."""
        commands = ["set system host-name 'router'"]
        output = StringIO()

        generate_restore_script(commands, output, include_header=False)

        result = output.getvalue()
        assert "# VyOS Configuration Restore Commands" not in result
        assert result.strip() == "set system host-name 'router'"


class TestSecretMappings:
    """Tests for SECRET_MAPPINGS configuration."""

    def test_all_mappings_have_required_fields(self) -> None:
        """Test that all mappings have required fields."""
        for mapping in SECRET_MAPPINGS:
            assert isinstance(mapping, SecretMapping)
            assert mapping.pattern
            assert mapping.env_var
            assert mapping.description

    def test_env_vars_have_vyos_prefix(self) -> None:
        """Test that all env vars have VYOS_ prefix."""
        for mapping in SECRET_MAPPINGS:
            assert mapping.env_var.startswith("VYOS_"), (
                f"{mapping.env_var} should start with VYOS_"
            )


class TestIntegration:
    """Integration tests for the complete workflow."""

    def test_full_workflow(self, tmp_path: Path) -> None:
        """Test complete backup parse and restore generation."""
        # Create backup file
        backup = tmp_path / "backup.txt"
        backup.write_text(
            dedent("""
            # VyOS Backup
            set system host-name 'router'
            set interfaces ethernet eth0 address '192.168.1.1/24'
            # set interfaces wireguard wg0 private-key '<VyOS秘密鍵>'
        """).strip()
        )

        # Create env file
        env_file = tmp_path / ".env"
        env_file.write_text("VYOS_WG_PRIVATE_KEY=test_private_key\n")

        # Load env and parse backup
        env_vars = load_env_file(env_file)
        commands = parse_backup_file(backup)
        processed, warnings = replace_placeholders(commands, env_vars)

        # Generate output
        output = StringIO()
        generate_restore_script(processed, output, include_header=False)
        result = output.getvalue()

        assert "set system host-name 'router'" in result
        assert "set interfaces ethernet eth0 address '192.168.1.1/24'" in result
        assert "set interfaces wireguard wg0 private-key 'test_private_key'" in result
        assert "<VyOS秘密鍵>" not in result

#!/usr/bin/env python3
"""
vyos_config.py のテスト
"""

import sys
from pathlib import Path

# scriptsディレクトリをパスに追加
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from vyos_config import (
    Config,
    generate_phase0,
    generate_phase1,
    generate_phase2,
    generate_phase3,
    generate_phase4,
    generate_phase5,
    generate_phase6,
    generate_all,
)


class TestConfig:
    """Config クラスのテスト"""

    def test_default_values(self):
        """デフォルト値が正しく設定されること"""
        cfg = Config()
        assert cfg.timezone == "Asia/Tokyo"
        assert cfg.wan_interface == "eth0"
        assert cfg.lan_interface == "eth1"
        assert cfg.wxr_interface == "eth2"
        assert cfg.wg_port == 51820

    def test_custom_values(self):
        """カスタム値で初期化できること"""
        cfg = Config(
            timezone="UTC",
            wan_interface="enp1s0",
            wg_port=12345,
        )
        assert cfg.timezone == "UTC"
        assert cfg.wan_interface == "enp1s0"
        assert cfg.wg_port == 12345


class TestGeneratePhase0:
    """Phase 0 生成のテスト"""

    def test_contains_timezone(self):
        """タイムゾーン設定が含まれること"""
        cfg = Config()
        commands = generate_phase0(cfg)
        output = "\n".join(commands)
        assert "set system time-zone Asia/Tokyo" in output

    def test_contains_ntp(self):
        """NTPサーバー設定が含まれること"""
        cfg = Config()
        commands = generate_phase0(cfg)
        output = "\n".join(commands)
        assert "set service ntp server ntp.nict.jp" in output
        assert "set service ntp server time.cloudflare.com" in output

    def test_contains_commit_save(self):
        """commit/saveが含まれること"""
        cfg = Config()
        commands = generate_phase0(cfg)
        output = "\n".join(commands)
        assert "commit" in output
        assert "save" in output


class TestGeneratePhase1:
    """Phase 1 生成のテスト"""

    def test_contains_ssh(self):
        """SSH設定が含まれること"""
        cfg = Config()
        commands = generate_phase1(cfg)
        output = "\n".join(commands)
        assert "set service ssh port 22" in output

    def test_with_ssh_key(self):
        """SSH公開鍵が指定されたとき設定に含まれること"""
        cfg = Config()
        test_key = "AAAAC3NzaC1lZDI1NTE5AAAAITestKey123"
        commands = generate_phase1(cfg, ssh_pubkey=test_key)
        output = "\n".join(commands)
        assert test_key in output
        assert "public-keys macbook" in output


class TestGeneratePhase2:
    """Phase 2 生成のテスト"""

    def test_contains_ipv6_autoconf(self):
        """IPv6 autoconf設定が含まれること"""
        cfg = Config()
        commands = generate_phase2(cfg)
        output = "\n".join(commands)
        assert "ipv6 address autoconf" in output

    def test_contains_dhcpv6_pd(self):
        """DHCPv6-PD設定が含まれること"""
        cfg = Config()
        commands = generate_phase2(cfg)
        output = "\n".join(commands)
        assert "dhcpv6-options pd 0 length 56" in output

    def test_contains_ra(self):
        """RA配布設定が含まれること"""
        cfg = Config()
        commands = generate_phase2(cfg)
        output = "\n".join(commands)
        assert "router-advert interface eth1" in output

    def test_contains_firewall(self):
        """ファイアウォール設定が含まれること"""
        cfg = Config()
        commands = generate_phase2(cfg)
        output = "\n".join(commands)
        assert "firewall ipv6 name WAN6_IN" in output
        assert "default-action drop" in output
        assert "icmpv6" in output


class TestGeneratePhase3:
    """Phase 3 生成のテスト"""

    def test_contains_wireguard(self):
        """WireGuard設定が含まれること"""
        cfg = Config()
        commands = generate_phase3(cfg)
        output = "\n".join(commands)
        assert "interfaces wireguard wg0" in output
        assert "port 51820" in output

    def test_contains_rate_limit(self):
        """rate limit設定が含まれること"""
        cfg = Config()
        commands = generate_phase3(cfg)
        output = "\n".join(commands)
        assert "recent count 10" in output
        assert "Rate limit WireGuard" in output

    def test_contains_vpn_restrictions(self):
        """VPNアクセス制限が含まれること"""
        cfg = Config()
        commands = generate_phase3(cfg)
        output = "\n".join(commands)
        assert "VPN_TO_LAN" in output
        assert "VPN_TO_WAN" in output

    def test_with_peers(self):
        """peer設定が正しく生成されること"""
        cfg = Config()
        peers = {
            "phone": {
                "pubkey": "TestPubKey123",
                "ipv4": "10.10.10.2/32",
                "ipv6": "fd00:vpn::2/128",
            }
        }
        commands = generate_phase3(cfg, peers=peers)
        output = "\n".join(commands)
        assert "peer phone" in output
        assert "TestPubKey123" in output


class TestGeneratePhase4:
    """Phase 4 生成のテスト"""

    def test_contains_wxr_interface(self):
        """WXR接続インターフェース設定が含まれること"""
        cfg = Config()
        commands = generate_phase4(cfg)
        output = "\n".join(commands)
        assert "eth2 description" in output
        assert "192.168.100.2/24" in output

    def test_contains_static_route(self):
        """スタティックルート設定が含まれること"""
        cfg = Config()
        commands = generate_phase4(cfg)
        output = "\n".join(commands)
        assert "route 0.0.0.0/0 next-hop 192.168.100.1" in output

    def test_contains_nat(self):
        """NAT設定が含まれること"""
        cfg = Config()
        commands = generate_phase4(cfg)
        output = "\n".join(commands)
        assert "nat source rule 100" in output
        assert "masquerade" in output


class TestGeneratePhase5:
    """Phase 5 生成のテスト"""

    def test_contains_ddns_placeholder(self):
        """DDNS設定のプレースホルダーが含まれること"""
        cfg = Config()
        commands = generate_phase5(cfg)
        output = "\n".join(commands)
        assert "dns dynamic" in output

    def test_contains_ddns_with_config(self):
        """DDNS設定が含まれること(設定あり)"""
        cfg = Config(
            ddns_zone="example.com",
            ddns_hostname="router.example.com",
            ddns_api_token="test-token",
        )
        commands = generate_phase5(cfg)
        output = "\n".join(commands)
        assert "zone example.com" in output
        assert "router.example.com" in output
        assert "password test-token" in output

    def test_contains_firewall_logging(self):
        """ファイアウォールログ設定が含まれること"""
        cfg = Config()
        commands = generate_phase5(cfg)
        output = "\n".join(commands)
        assert "default-log" in output


class TestGeneratePhase6:
    """Phase 6 生成のテスト"""

    def test_contains_backup_dir(self):
        """バックアップディレクトリ作成が含まれること"""
        cfg = Config()
        commands = generate_phase6(cfg)
        output = "\n".join(commands)
        assert "/config/backup" in output

    def test_contains_task_scheduler(self):
        """タスクスケジューラー設定が含まれること"""
        cfg = Config()
        commands = generate_phase6(cfg)
        output = "\n".join(commands)
        assert "task-scheduler" in output
        assert "daily-backup" in output


class TestGenerateAll:
    """全フェーズ生成のテスト"""

    def test_contains_all_phases(self):
        """全フェーズが含まれること"""
        cfg = Config()
        commands = generate_all(cfg)
        output = "\n".join(commands)
        assert "Phase 0" in output
        assert "Phase 1" in output
        assert "Phase 2" in output
        assert "Phase 3" in output
        assert "Phase 4" in output
        assert "Phase 5" in output
        assert "Phase 6" in output


class TestInterfaceCustomization:
    """インターフェース名カスタマイズのテスト"""

    def test_custom_interface_names(self):
        """カスタムインターフェース名が反映されること"""
        cfg = Config(
            wan_interface="enp1s0",
            lan_interface="enp2s0",
            wxr_interface="enp3s0",
        )
        commands = generate_phase2(cfg)
        output = "\n".join(commands)
        assert "enp1s0" in output
        assert "enp2s0" in output

        commands = generate_phase4(cfg)
        output = "\n".join(commands)
        assert "enp3s0" in output


if __name__ == "__main__":
    import pytest
    pytest.main([__file__, "-v"])

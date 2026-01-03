#!/usr/bin/env python3
"""
VyOS Configuration Generator

VyOS設定コマンドを生成するPythonスクリプト。
VyOSはDebian 12ベースなのでPython 3が利用可能。

使い方:
  1. このスクリプトをVyOSにコピー
  2. config.yaml を編集して環境に合わせる
  3. python3 vyos_config.py phase0  # Phase 0の設定を出力
  4. 出力されたコマンドを確認してVyOSで実行

注意:
  - このスクリプトは設定コマンドを「出力」するだけ
  - 実際の適用は手動で行う（安全のため）
"""

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

try:
    import yaml
except ImportError:
    yaml = None


@dataclass
class Config:
    """設定パラメータ"""

    # タイムゾーン
    timezone: str = "Asia/Tokyo"

    # NTPサーバー
    ntp_servers: tuple = ("ntp.nict.jp", "time.cloudflare.com")

    # インターフェース名
    # Intel X540-T2 Port1/Port2, オンボード1GbE
    wan_interface: str = "enp1s0f0"  # WAN (10GbE)
    lan_interface: str = "enp1s0f1"  # LAN (10GbE)
    wxr_interface: str = "eno1"      # WXR接続 (1GbE オンボード、要確認)

    # LAN設定
    lan_ipv4: str = "192.168.1.1/24"
    lan_ipv4_network: str = "192.168.1.0/24"

    # WXR接続セグメント
    wxr_segment_self: str = "192.168.100.2/24"
    wxr_segment_gw: str = "192.168.100.1"

    # DHCPv6-PD
    pd_length: int = 56
    pd_sla_id: int = 1

    # DNS (IPv6)
    dns_ipv6: str = "2001:4860:4860::8888"  # Google DNS

    # WireGuard
    wg_interface: str = "wg0"
    wg_port: int = 51820
    wg_ipv4: str = "10.10.10.1/24"
    wg_ipv6: str = "fd00:vpn::1/64"

    # DDNS
    ddns_zone: str = ""
    ddns_hostname: str = ""
    ddns_api_token: str = ""

    @classmethod
    def from_yaml(cls, path: Path) -> "Config":
        """YAMLファイルから設定を読み込む"""
        if yaml is None:
            print("Warning: PyYAML not installed, using defaults", file=sys.stderr)
            return cls()

        if not path.exists():
            print(f"Warning: {path} not found, using defaults", file=sys.stderr)
            return cls()

        with open(path) as f:
            data = yaml.safe_load(f)

        return cls(**{k: v for k, v in data.items() if hasattr(cls, k)})


def generate_phase0(cfg: Config) -> list[str]:
    """Phase 0: 基本設定"""
    commands = [
        "# ========================================",
        "# Phase 0: VyOS基本設定",
        "# ========================================",
        "",
        "configure",
        "",
        "# タイムゾーン設定",
        f"set system time-zone {cfg.timezone}",
        "",
        "# NTPサーバー設定",
    ]

    for server in cfg.ntp_servers:
        commands.append(f"set service ntp server {server}")

    commands.extend(
        [
            "",
            "commit",
            "save",
            "",
            "# 確認コマンド:",
            "# show date",
            "# show ntp",
        ]
    )

    return commands


def generate_phase1(cfg: Config, ssh_listen_ip: str = "", ssh_pubkey: str = "") -> list[str]:
    """Phase 1: SSH設定"""
    commands = [
        "# ========================================",
        "# Phase 1: SSH有効化",
        "# ========================================",
        "",
        "configure",
        "",
        "# SSH有効化",
        "set service ssh port 22",
    ]

    if ssh_listen_ip:
        commands.append(f"set service ssh listen-address {ssh_listen_ip}")
    else:
        commands.append(f"# set service ssh listen-address <LAN側IPアドレス>  # 要設定")

    commands.extend(
        [
            "",
            "commit",
            "save",
            "",
        ]
    )

    if ssh_pubkey:
        commands.extend(
            [
                "# SSH公開鍵登録",
                "set system login user vyos authentication public-keys macbook type ssh-ed25519",
                f"set system login user vyos authentication public-keys macbook key {ssh_pubkey}",
                "",
                "commit",
                "save",
                "",
                "# === 接続テスト成功後のみ実行 ===",
                "# set service ssh disable-password-authentication",
                "# commit",
                "# save",
            ]
        )
    else:
        commands.extend(
            [
                "# 公開鍵登録 (Mac側で `cat ~/.ssh/id_ed25519-touch-id.pub` を実行して取得)",
                "# set system login user vyos authentication public-keys macbook type ssh-ed25519",
                "# set system login user vyos authentication public-keys macbook key <公開鍵>",
            ]
        )

    return commands


def generate_phase2(cfg: Config) -> list[str]:
    """Phase 2: IPv6基盤構築"""
    commands = [
        "# ========================================",
        "# Phase 2: IPv6基盤構築",
        "# ========================================",
        "",
        "# --- 2-1: RA受信・DHCPv6-PD取得 ---",
        "",
        "configure",
        "",
        f"set interfaces ethernet {cfg.wan_interface} description 'WAN'",
        f"set interfaces ethernet {cfg.wan_interface} ipv6 address autoconf",
        f"set interfaces ethernet {cfg.wan_interface} dhcpv6-options pd 0 length {cfg.pd_length}",
        f"set interfaces ethernet {cfg.wan_interface} dhcpv6-options pd 0 interface {cfg.lan_interface} sla-id {cfg.pd_sla_id}",
        "",
        "commit",
        "save",
        "",
        "# 確認: show interfaces",
        "",
        "# --- 2-2: LAN側RA配布設定 ---",
        "",
        f"set service router-advert interface {cfg.lan_interface} prefix ::/64",
        f"set service router-advert interface {cfg.lan_interface} name-server {cfg.dns_ipv6}",
        "",
        "commit",
        "save",
        "",
        "# --- 2-3: IPv6ファイアウォール設定 ---",
        "",
        "set firewall ipv6 name WAN6_IN default-action drop",
        "",
        "# 確立済み/関連セッション許可",
        "set firewall ipv6 name WAN6_IN rule 10 action accept",
        "set firewall ipv6 name WAN6_IN rule 10 state established enable",
        "set firewall ipv6 name WAN6_IN rule 10 state related enable",
        "",
        "# ICMPv6 (必要なタイプのみ許可)",
        "set firewall ipv6 name WAN6_IN rule 20 action accept",
        "set firewall ipv6 name WAN6_IN rule 20 protocol icmpv6",
        "set firewall ipv6 name WAN6_IN rule 20 icmpv6 type echo-request",
        "",
        "set firewall ipv6 name WAN6_IN rule 21 action accept",
        "set firewall ipv6 name WAN6_IN rule 21 protocol icmpv6",
        "set firewall ipv6 name WAN6_IN rule 21 icmpv6 type neighbor-solicitation",
        "",
        "set firewall ipv6 name WAN6_IN rule 22 action accept",
        "set firewall ipv6 name WAN6_IN rule 22 protocol icmpv6",
        "set firewall ipv6 name WAN6_IN rule 22 icmpv6 type neighbor-advertisement",
        "",
        "set firewall ipv6 name WAN6_IN rule 23 action accept",
        "set firewall ipv6 name WAN6_IN rule 23 protocol icmpv6",
        "set firewall ipv6 name WAN6_IN rule 23 icmpv6 type router-solicitation",
        "",
        "set firewall ipv6 name WAN6_IN rule 24 action accept",
        "set firewall ipv6 name WAN6_IN rule 24 protocol icmpv6",
        "set firewall ipv6 name WAN6_IN rule 24 icmpv6 type router-advertisement",
        "",
        "# インターフェースに適用",
        f"set interfaces ethernet {cfg.wan_interface} firewall in ipv6-name WAN6_IN",
        "",
        "commit",
        "save",
    ]

    return commands


def generate_phase3(cfg: Config, peers: Optional[dict] = None) -> list[str]:
    """Phase 3: WireGuard VPN"""
    commands = [
        "# ========================================",
        "# Phase 3: WireGuard VPN",
        "# ========================================",
        "",
        "# --- 3-1: 鍵生成・インターフェース作成 ---",
        "",
        "# 鍵生成 (operationalモードで実行)",
        "# generate wireguard default-keypair",
        "# show wireguard keypairs pubkey default",
        "",
        "configure",
        "",
        f"set interfaces wireguard {cfg.wg_interface} address {cfg.wg_ipv4}",
        f"set interfaces wireguard {cfg.wg_interface} port {cfg.wg_port}",
        f"set interfaces wireguard {cfg.wg_interface} private-key default",
        f"set interfaces wireguard {cfg.wg_interface} address {cfg.wg_ipv6}",
        "",
    ]

    # peer設定
    if peers:
        commands.append("# Peer設定")
        for name, peer in peers.items():
            if "pubkey" in peer:
                ipv4 = peer.get("ipv4", f"10.10.10.{len(peers) + 1}/32")
                ipv6 = peer.get("ipv6", f"fd00:vpn::{len(peers) + 1}/128")
                commands.append(
                    f"set interfaces wireguard {cfg.wg_interface} peer {name} allowed-ips {ipv4}"
                )
                commands.append(
                    f"set interfaces wireguard {cfg.wg_interface} peer {name} allowed-ips {ipv6}"
                )
                commands.append(
                    f"set interfaces wireguard {cfg.wg_interface} peer {name} public-key {peer['pubkey']}"
                )
                commands.append("")
    else:
        commands.extend(
            [
                "# Peer設定 (クライアントごとに追加)",
                f"# set interfaces wireguard {cfg.wg_interface} peer phone allowed-ips 10.10.10.2/32",
                f"# set interfaces wireguard {cfg.wg_interface} peer phone allowed-ips fd00:vpn::2/128",
                f"# set interfaces wireguard {cfg.wg_interface} peer phone public-key <クライアント公開鍵>",
                "",
            ]
        )

    commands.extend(
        [
            "commit",
            "save",
            "",
            "# --- 3-2: ファイアウォール許可 ---",
            "",
            "# WireGuard rate limit (1分間に10回以上の新規接続をdrop)",
            "set firewall ipv6 name WAN6_IN rule 25 action drop",
            "set firewall ipv6 name WAN6_IN rule 25 protocol udp",
            f"set firewall ipv6 name WAN6_IN rule 25 destination port {cfg.wg_port}",
            "set firewall ipv6 name WAN6_IN rule 25 recent count 10",
            "set firewall ipv6 name WAN6_IN rule 25 recent time minute",
            "set firewall ipv6 name WAN6_IN rule 25 state new enable",
            "set firewall ipv6 name WAN6_IN rule 25 description 'Rate limit WireGuard'",
            "",
            "# WireGuard許可",
            "set firewall ipv6 name WAN6_IN rule 30 action accept",
            "set firewall ipv6 name WAN6_IN rule 30 protocol udp",
            f"set firewall ipv6 name WAN6_IN rule 30 destination port {cfg.wg_port}",
            "set firewall ipv6 name WAN6_IN rule 30 description 'Allow WireGuard'",
            "",
            "commit",
            "save",
            "",
            "# --- 3-3: VPNアクセス制限 ---",
            "",
            "# VPN → LAN 制限 (VyOS自身のみ許可)",
            "set firewall ipv4 name VPN_TO_LAN default-action drop",
            "set firewall ipv4 name VPN_TO_LAN rule 10 action accept",
            f"set firewall ipv4 name VPN_TO_LAN rule 10 destination address {cfg.wg_ipv4.split('/')[0]}",
            "set firewall ipv4 name VPN_TO_LAN rule 10 description 'Allow access to VyOS only'",
            "",
            "set firewall ipv6 name VPN6_TO_LAN default-action drop",
            "set firewall ipv6 name VPN6_TO_LAN rule 10 action accept",
            f"set firewall ipv6 name VPN6_TO_LAN rule 10 destination address {cfg.wg_ipv6.split('/')[0]}",
            "set firewall ipv6 name VPN6_TO_LAN rule 10 description 'Allow access to VyOS only'",
            "",
            f"set interfaces ethernet {cfg.lan_interface} firewall in name VPN_TO_LAN",
            f"set interfaces ethernet {cfg.lan_interface} firewall in ipv6-name VPN6_TO_LAN",
            "",
            "# VPN → WAN 禁止",
            "set firewall ipv4 name VPN_TO_WAN default-action drop",
            "set firewall ipv4 name VPN_TO_WAN rule 1 action drop",
            "set firewall ipv4 name VPN_TO_WAN rule 1 description 'Block VPN to Internet'",
            "",
            "set firewall ipv6 name VPN6_TO_WAN default-action drop",
            "set firewall ipv6 name VPN6_TO_WAN rule 1 action drop",
            "set firewall ipv6 name VPN6_TO_WAN rule 1 description 'Block VPN to Internet'",
            "",
            f"set interfaces ethernet {cfg.wan_interface} firewall in name VPN_TO_WAN",
            f"set interfaces ethernet {cfg.wan_interface} firewall in ipv6-name VPN6_TO_WAN",
            "",
            "commit",
            "save",
        ]
    )

    return commands


def generate_phase4(cfg: Config) -> list[str]:
    """Phase 4: WXR隔離・IPv4ルーティング"""
    commands = [
        "# ========================================",
        "# Phase 4: WXR隔離・IPv4ルーティング",
        "# ========================================",
        "",
        "# 注意: 4-1, 4-2はWXR管理画面での設定が必要",
        "",
        "# --- 4-3: 別セグメント構築 ---",
        "",
        "configure",
        "",
        f"set interfaces ethernet {cfg.wxr_interface} description 'To WXR LAN (IPv4 transit)'",
        f"set interfaces ethernet {cfg.wxr_interface} address {cfg.wxr_segment_self}",
        "",
        "commit",
        "save",
        "",
        "# 疎通確認: ping 192.168.100.1",
        "",
        "# --- 4-4: IPv4ルーティング ---",
        "",
        "# 全IPv4をWXR経由に設定",
        f"set protocols static route 0.0.0.0/0 next-hop {cfg.wxr_segment_gw}",
        "",
        "# LAN側インターフェースのIPv4アドレス設定",
        f"set interfaces ethernet {cfg.lan_interface} address {cfg.lan_ipv4}",
        "",
        "# LAN → WXR方向のNAT(マスカレード)",
        f"set nat source rule 100 outbound-interface name {cfg.wxr_interface}",
        f"set nat source rule 100 source address {cfg.lan_ipv4_network}",
        "set nat source rule 100 translation address masquerade",
        "",
        "commit",
        "save",
        "",
        "# 確認コマンド:",
        "# show ip route",
        "# ping 8.8.8.8",
        "# curl -4 ifconfig.me",
    ]

    return commands


def generate_phase5(cfg: Config) -> list[str]:
    """Phase 5: 運用設定"""
    commands = [
        "# ========================================",
        "# Phase 5: 運用設定",
        "# ========================================",
        "",
        "# --- 5-1: Cloudflare DDNS設定 ---",
        "",
        "configure",
        "",
    ]

    if cfg.ddns_zone and cfg.ddns_hostname:
        commands.extend(
            [
                f"set service dns dynamic name cloudflare address interface {cfg.wan_interface}",
                "set service dns dynamic name cloudflare protocol cloudflare",
                f"set service dns dynamic name cloudflare zone {cfg.ddns_zone}",
                f"set service dns dynamic name cloudflare host-name {cfg.ddns_hostname}",
            ]
        )
        if cfg.ddns_api_token:
            commands.append(
                f"set service dns dynamic name cloudflare password {cfg.ddns_api_token}"
            )
        else:
            commands.append(
                "set service dns dynamic name cloudflare password <CloudflareAPIトークン>"
            )
        commands.append("set service dns dynamic name cloudflare ip-version ipv6")
    else:
        commands.extend(
            [
                "# DDNS設定 (config.yaml で ddns_zone, ddns_hostname を設定)",
                f"# set service dns dynamic name cloudflare address interface {cfg.wan_interface}",
                "# set service dns dynamic name cloudflare protocol cloudflare",
                "# set service dns dynamic name cloudflare zone <your-domain.com>",
                "# set service dns dynamic name cloudflare host-name <router.your-domain.com>",
                "# set service dns dynamic name cloudflare password <CloudflareAPIトークン>",
                "# set service dns dynamic name cloudflare ip-version ipv6",
            ]
        )

    commands.extend(
        [
            "",
            "commit",
            "save",
            "",
            "# 確認: show dns dynamic status",
            "",
            "# --- 5-2: ファイアウォールログ設定 ---",
            "",
            "set firewall ipv6 name WAN6_IN default-log",
            "set firewall ipv4 name VPN_TO_LAN default-log",
            "set firewall ipv4 name VPN_TO_WAN default-log",
            "set firewall ipv6 name VPN6_TO_LAN default-log",
            "set firewall ipv6 name VPN6_TO_WAN default-log",
            "",
            "# rate limitでdropされたパケットのログ",
            "set firewall ipv6 name WAN6_IN rule 25 log",
            "",
            "commit",
            "save",
        ]
    )

    return commands


def generate_phase6(cfg: Config) -> list[str]:
    """Phase 6: バックアップ体制"""
    commands = [
        "# ========================================",
        "# Phase 6: バックアップ体制",
        "# ========================================",
        "",
        "# --- 6-1: バックアップディレクトリ作成 ---",
        "",
        "# operationalモードで実行",
        "sudo mkdir -p /config/backup",
        "sudo mkdir -p /config/scripts",
        "",
        "# --- 6-2: 自動バックアップ設定 ---",
        "",
        "configure",
        "",
        "set system task-scheduler task daily-backup crontab-spec '0 3 * * *'",
        "set system task-scheduler task daily-backup executable path '/config/scripts/backup.sh'",
        "",
        "commit",
        "save",
        "",
        "# --- 6-3: バックアップスクリプト作成 ---",
        "",
        "# /config/scripts/backup.sh として保存:",
        "# #!/bin/bash",
        '# BACKUP_DIR="/config/backup"',
        '# DATE=$(date +%Y%m%d)',
        "# MAX_BACKUPS=30",
        '# cp /config/config.boot "${BACKUP_DIR}/config-${DATE}.boot"',
        '# find "${BACKUP_DIR}" -name "config-*.boot" -mtime +${MAX_BACKUPS} -delete',
        "",
        "# chmod +x /config/scripts/backup.sh",
    ]

    return commands


def generate_all(cfg: Config) -> list[str]:
    """全フェーズを出力"""
    commands = []
    commands.extend(generate_phase0(cfg))
    commands.append("")
    commands.extend(generate_phase1(cfg))
    commands.append("")
    commands.extend(generate_phase2(cfg))
    commands.append("")
    commands.extend(generate_phase3(cfg))
    commands.append("")
    commands.extend(generate_phase4(cfg))
    commands.append("")
    commands.extend(generate_phase5(cfg))
    commands.append("")
    commands.extend(generate_phase6(cfg))
    return commands


def main():
    parser = argparse.ArgumentParser(
        description="VyOS設定コマンド生成スクリプト",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  python3 vyos_config.py phase0              # Phase 0の設定を出力
  python3 vyos_config.py phase2 -c my.yaml   # 設定ファイル指定
  python3 vyos_config.py all                 # 全フェーズを出力
  python3 vyos_config.py phase1 --ssh-key "AAAAC3NzaC1..."  # SSH公開鍵指定
        """,
    )

    parser.add_argument(
        "phase",
        choices=["phase0", "phase1", "phase2", "phase3", "phase4", "phase5", "phase6", "all"],
        help="生成するフェーズ",
    )
    parser.add_argument(
        "-c",
        "--config",
        type=Path,
        default=Path("config.yaml"),
        help="設定ファイルのパス (default: config.yaml)",
    )
    parser.add_argument(
        "--ssh-listen-ip",
        help="SSH待ち受けIPアドレス (Phase 1用)",
    )
    parser.add_argument(
        "--ssh-key",
        help="SSH公開鍵 (Phase 1用, AAAAC3NzaC1...部分のみ)",
    )

    args = parser.parse_args()

    cfg = Config.from_yaml(args.config)

    generators = {
        "phase0": lambda: generate_phase0(cfg),
        "phase1": lambda: generate_phase1(cfg, args.ssh_listen_ip, args.ssh_key),
        "phase2": lambda: generate_phase2(cfg),
        "phase3": lambda: generate_phase3(cfg),
        "phase4": lambda: generate_phase4(cfg),
        "phase5": lambda: generate_phase5(cfg),
        "phase6": lambda: generate_phase6(cfg),
        "all": lambda: generate_all(cfg),
    }

    commands = generators[args.phase]()
    print("\n".join(commands))


if __name__ == "__main__":
    main()

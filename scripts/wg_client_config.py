#!/usr/bin/env python3
"""
WireGuard クライアント設定生成スクリプト

VyOSサーバーに接続するためのクライアント設定ファイル(.conf)を生成する。
QRコードの生成にも対応(qrencodeがインストールされている場合)。

使い方:
  python3 wg_client_config.py --name phone --server-pubkey <VyOS公開鍵>
  python3 wg_client_config.py --name laptop --server-pubkey <VyOS公開鍵> --qr
"""

import argparse
import subprocess
import sys
from pathlib import Path


def generate_keypair() -> tuple[str, str]:
    """WireGuard鍵ペアを生成"""
    try:
        # wg コマンドがあるか確認
        private_key = subprocess.run(
            ["wg", "genkey"], capture_output=True, text=True, check=True
        ).stdout.strip()

        public_key = subprocess.run(
            ["wg", "pubkey"],
            input=private_key,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

        return private_key, public_key
    except FileNotFoundError:
        print("Error: wg コマンドが見つかりません", file=sys.stderr)
        print("  macOS: brew install wireguard-tools", file=sys.stderr)
        print("  Ubuntu: sudo apt install wireguard-tools", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error: 鍵生成に失敗: {e}", file=sys.stderr)
        sys.exit(1)


def generate_config(
    name: str,
    private_key: str,
    ipv4: str,
    ipv6: str,
    server_pubkey: str,
    endpoint: str,
    allowed_ips: list[str],
) -> str:
    """WireGuardクライアント設定を生成"""
    config = f"""[Interface]
# Client: {name}
PrivateKey = {private_key}
Address = {ipv4}, {ipv6}

[Peer]
# VyOS Server
PublicKey = {server_pubkey}
Endpoint = {endpoint}
AllowedIPs = {', '.join(allowed_ips)}
PersistentKeepalive = 25
"""
    return config


def generate_qr(config: str) -> None:
    """QRコードを生成(ターミナルに表示)"""
    try:
        subprocess.run(
            ["qrencode", "-t", "ANSIUTF8"],
            input=config,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print("Warning: qrencode が見つかりません", file=sys.stderr)
        print("  macOS: brew install qrencode", file=sys.stderr)
        print("  Ubuntu: sudo apt install qrencode", file=sys.stderr)


def print_vyos_commands(name: str, public_key: str, ipv4: str, ipv6: str) -> None:
    """VyOS側で実行するpeer登録コマンドを出力"""
    print("\n# VyOS側で実行するpeer登録コマンド:")
    print("configure")
    print(f"set interfaces wireguard wg0 peer {name} allowed-ips {ipv4}")
    print(f"set interfaces wireguard wg0 peer {name} allowed-ips {ipv6}")
    print(f"set interfaces wireguard wg0 peer {name} public-key {public_key}")
    print("commit")
    print("save")


def main():
    parser = argparse.ArgumentParser(
        description="WireGuardクライアント設定生成",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  # 基本的な使い方
  python3 wg_client_config.py --name phone --server-pubkey <VyOS公開鍵>

  # QRコード生成
  python3 wg_client_config.py --name phone --server-pubkey <VyOS公開鍵> --qr

  # カスタムIPアドレス
  python3 wg_client_config.py --name laptop \\
    --server-pubkey <VyOS公開鍵> \\
    --ipv4 10.10.10.5/32 \\
    --ipv6 fd00:vpn::5/128
        """,
    )

    parser.add_argument("--name", required=True, help="クライアント名 (例: phone, laptop)")
    parser.add_argument("--server-pubkey", required=True, help="VyOSサーバーの公開鍵")
    parser.add_argument(
        "--endpoint",
        default="router.example.com:51820",
        help="VyOSサーバーのエンドポイント (default: router.example.com:51820)",
    )
    parser.add_argument("--ipv4", help="クライアントIPv4アドレス (default: 自動採番)")
    parser.add_argument("--ipv6", help="クライアントIPv6アドレス (default: 自動採番)")
    parser.add_argument(
        "--client-id",
        type=int,
        default=2,
        help="クライアントID (IP採番用, default: 2)",
    )
    parser.add_argument(
        "--allowed-ips",
        default="10.10.10.1/32,fd00:vpn::1/128",
        help="許可するIP (default: VyOSのみ)",
    )
    parser.add_argument("--qr", action="store_true", help="QRコードを生成")
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="出力ファイル (default: stdout)",
    )
    parser.add_argument(
        "--private-key",
        help="既存の秘密鍵を使用 (指定しない場合は新規生成)",
    )

    args = parser.parse_args()

    # IP アドレス設定
    ipv4 = args.ipv4 or f"10.10.10.{args.client_id}/32"
    ipv6 = args.ipv6 or f"fd00:vpn::{args.client_id}/128"

    # 鍵生成または読み込み
    if args.private_key:
        private_key = args.private_key
        public_key = subprocess.run(
            ["wg", "pubkey"],
            input=private_key,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    else:
        print("鍵ペアを生成中...", file=sys.stderr)
        private_key, public_key = generate_keypair()

    # 設定生成
    allowed_ips = [ip.strip() for ip in args.allowed_ips.split(",")]
    config = generate_config(
        name=args.name,
        private_key=private_key,
        ipv4=ipv4,
        ipv6=ipv6,
        server_pubkey=args.server_pubkey,
        endpoint=args.endpoint,
        allowed_ips=allowed_ips,
    )

    # 出力
    if args.output:
        args.output.write_text(config)
        args.output.chmod(0o600)
        print(f"設定を保存しました: {args.output}", file=sys.stderr)
    else:
        print(config)

    # VyOS側コマンド
    print_vyos_commands(args.name, public_key, ipv4, ipv6)

    # QRコード
    if args.qr:
        print("\n# QRコード:")
        generate_qr(config)


if __name__ == "__main__":
    main()

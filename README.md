# 自作ルーター構築プロジェクト

BIGLOBE光(10Gbps)環境で、MAP-Eの制約を回避しつつ10Gbpsを最大限活用する自作ルーターの構築手順書。

## 設計思想

- **IPv6を主役**: 10Gbps活用可能、WXRを一切通さない
- **IPv4は例外扱い**: ポリシールーティングでWXRへ転送
- **MAP-Eは保険**: 捨てず、重要視もしない

## 物理構成

```
[ONU] ── [LXW-10G5] ─┬─ 10G ── [自作ルーター] ── [LAN]
                     │                │
                     │           (別セグメント 1G)
                     │                │
                     └─ 10G ── [WXR9300BE6P]
                               (MAP-E専用)
```

- **LXW-10G5**: BUFFALO 10GbE L2スイッチ (5ポート)

## 環境

| 項目 | 内容 |
|------|------|
| OS | VyOS Rolling Release |
| 本体 | HP ProDesk 600 G4 SFF |
| eth0 | オンボード (1GbE) - WXR接続用 |
| eth1 | Intel X540-T2 Port2 (10GbE) - WAN |
| eth2 | Intel X540-T2 Port1 (10GbE) - LAN |
| (未使用) | RTL8126 (5GbE) - フレキシブル |
| L2スイッチ | BUFFALO LXW-10G5 |
| ISP | BIGLOBE (IPv6 IPoE + MAP-E) |
| 既存ルーター | Buffalo WXR9300BE6P |

### WXR接続用別セグメント (192.168.100.x)

自作ルーターとWXR9300BE6Pを1GbEオンボードNICで直結し、IPv4転送専用の別セグメントを構築する。

- 自作ルーター側: 192.168.100.2/24
- WXR側 (LAN): 192.168.100.1/24 (DHCPサーバー無効)
- 用途: IPv4トラフィックをWXR経由でMAP-Eに転送
- 帯域: 1Gbps上限 (IPv4は例外扱いなので問題なし)

## 実装フェーズ

| Phase | 内容 | ドキュメント |
|-------|------|-------------|
| 0 | VyOSインストール・基本設定 | [docs/phase0-install.md](docs/phase0-install.md) |
| 1 | LAN側SSH有効化 | [docs/phase1-ssh.md](docs/phase1-ssh.md) |
| 2 | IPv6基盤構築 | [docs/phase2-ipv6.md](docs/phase2-ipv6.md) |
| 3 | WireGuard VPN | [docs/phase3-wireguard.md](docs/phase3-wireguard.md) |
| 4 | WXR隔離・IPv4ルーティング | [docs/phase4-wxr-routing.md](docs/phase4-wxr-routing.md) |
| 5 | 運用設定 | [docs/phase5-operations.md](docs/phase5-operations.md) |
| 6 | バックアップ体制 | [docs/phase6-backup.md](docs/phase6-backup.md) |

リファレンス情報: [docs/reference.md](docs/reference.md)

## 進捗管理

[CLAUDE.md](CLAUDE.md) にチェックリストがあります。

## セキュリティ考慮事項

- SSHはLAN側のみ、WAN側はWireGuard経由でアクセス
- WireGuardにrate limit適用（DoS対策）
- VPNクライアントはVyOSのみアクセス可能（踏み台防止）
- ICMPv6は必要なタイプのみ許可
- 公開鍵認証 + TouchID連携

## 注意

このリポジトリには機密情報（APIトークン、秘密鍵等）を含めないでください。

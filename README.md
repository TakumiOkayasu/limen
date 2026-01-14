# BIGLOBE 10Gbps 自作ルーター

VyOSベースの自作ルーターで、BIGLOBE光 10Gbps回線を最大限活用する。

## 現在の状態

| 項目 | 状態 | 備考 |
|------|------|------|
| IPv6 | **稼働中** | 10Gbps (ONU直結) |
| IPv4 | **稼働中** | WXR経由MAP-E (1Gbps上限) |
| WireGuard VPN | **稼働中** | 外部からVyOSにSSH可能 |
| Cloudflare DDNS | **稼働中** | router.murata-lab.net |
| RTL8126 (5GbE) | **CI対応中** | カスタムISOでビルド中 |

## 設計思想

- **IPv6を主役**: 10Gbps活用、ONUに直結
- **IPv4は例外扱い**: WXR経由でMAP-E処理
- **シンプルさ優先**: 複雑なMAP-E自作実装は避ける

## 物理構成

```
[ONU] ── [LXW-10G5] ─┬─ 10G ── [自作ルーター] ── 10G ── [LAN]
                     │         (eth1: WAN)      (eth2)
                     │              │
                     │         1G (eth0)
                     │              │
                     └─ 10G ── [WXR9300BE6P] ── (MAP-E)
                               192.168.100.1
```

## ハードウェア

| 機器 | 型番 | 用途 |
|------|------|------|
| ルーター本体 | HP ProDesk 600 G4 SFF | VyOS稼働 |
| 10GbE NIC | Intel X540-T2 | WAN/LAN |
| 5GbE NIC | Binardat RTL8126 | 将来用 (未使用) |
| L2スイッチ | BUFFALO LXW-10G5 | ONU分岐 |
| MAP-Eルーター | BUFFALO WXR9300BE6P | IPv4専用 |

## NIC構成

| VyOS名 | NIC | 速度 | 用途 |
|--------|-----|------|------|
| eth0 | オンボード | 1GbE | WXR接続 (192.168.100.2) |
| eth1 | X540-T2 Port2 | 10GbE | WAN |
| eth2 | X540-T2 Port1 | 10GbE | LAN (192.168.1.1) |

## トラフィックフロー

| プロトコル | 経路 | 速度 |
|-----------|------|------|
| IPv6 | LAN → VyOS → ONU → NGN | 10Gbps |
| IPv4 | LAN → VyOS → WXR → MAP-E | 1Gbps |

## WireGuard VPN

外部ネットワークからVyOSに安全にアクセスするためのVPN。

| 項目 | 値 |
|------|-----|
| サーバーアドレス | 10.10.10.1/24, fd00:10:10:10::1/64 |
| ポート | 51820 (UDP/IPv6) |
| Endpoint | router.murata-lab.net:51820 |

### アクセス制限

- VPNクライアント → VyOS: **許可**
- VPNクライアント → LAN: **禁止**
- VPNクライアント → インターネット: **禁止**

踏み台として使用されることを防ぐため、VPNからはVyOSのみにアクセス可能。

## ドキュメント

### 実装ガイド

| Phase | 内容 | 状態 |
|-------|------|------|
| [Phase 0](docs/phase0-install.md) | VyOSインストール | 完了 |
| [Phase 1](docs/phase1-ssh.md) | SSH設定 | 完了 |
| [Phase 2](docs/phase2-ipv6.md) | IPv6基盤 (RA/DHCPv6-PD) | 完了 |
| [Phase 3](docs/phase3-wireguard.md) | WireGuard VPN | 完了 |
| [Phase 4](docs/phase4-wxr-routing.md) | WXR隔離・IPv4ルーティング | 完了 |
| [Phase 5](docs/phase5-operations.md) | 運用設定 (DDNS, ログ) | 完了 |
| [Phase 6](docs/phase6-backup.md) | バックアップ | 完了 |

### リファレンス

- [reference.md](docs/reference.md) - VyOS操作、FWルール、環境情報
- [hardware-specs.md](docs/hardware-specs.md) - 機材詳細スペック、MACアドレス

### トラブルシューティング

- [troubleshooting-ipv6.md](docs/troubleshooting-ipv6.md) - IPv6疎通問題
- [troubleshooting-dhcpv6-pd.md](docs/troubleshooting-dhcpv6-pd.md) - DHCPv6-PD取得 (DUID-LL必須)
- [troubleshooting-ra-missing.md](docs/troubleshooting-ra-missing.md) - RA設定消失
- [failure-log-2026-01-07-kernel-update.md](docs/failure-log-2026-01-07-kernel-update.md) - カーネル更新失敗記録

## CI/CD

| ワークフロー | 用途 |
|-------------|------|
| build-vyos-custom-iso.yml | VyOSカスタムISO (カーネル + 署名済みr8126) のビルド |
| on-failure.yml | CI失敗時の自動修正PR作成 (reusable workflow) |
| dependabot-auto-merge.yml | Dependabot PRの自動マージ |
| lint-workflows.yml | ワークフローYAMLの構文チェック |

## 既知の問題と対応状況

### X540-T2 オーバーヒート (解決済み)

Intel X540-T2は発熱が大きく、ヒートシンクなしで長時間稼働するとオーバーヒートで停止する。

**対応**: ヒートシンク (40x40mm) を取り付け済み。安定稼働中。

### RTL8126 モジュール署名 (CI対応中)

VyOSはMODULE_SIG_FORCE=yでビルドされており、署名なしモジュールをロードできない。

**対応**: CIでカスタムカーネル+署名済みr8126モジュールを含むISOをビルド中。
- ワークフロー: `.github/workflows/build-vyos-custom-iso.yml`
- ビルド時間: 約80分 (GitHub Actions標準ランナー)
- 完成後、eth0 (1GbE) をRTL8126 (5GbE) に置き換え予定

## セキュリティ

- このリポジトリには機密情報 (APIトークン、秘密鍵等) を含めない
- WireGuard鍵は `~/.wireguard/` にローカル保存
- Cloudflare APIトークンはVyOS設定内に保存 (リポジトリ外)

## ライセンス

このプロジェクトは個人利用を目的としています。

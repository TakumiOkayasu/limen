# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# BIGLOBE + MAP-E + 10Gbps 自作ルーター構築プロジェクト

## プロジェクト概要

BIGLOBE光(10Gbps)環境で、MAP-Eの制約を回避しつつ10Gbpsを最大限活用する自作ルーターを構築する。

### 設計思想

- **IPv6を主役**: 10Gbps活用可能、WXRを一切通さない
- **IPv4は例外扱い**: ポリシールーティングでWXRへ転送
- **MAP-Eは保険**: 捨てず、重要視もしない

### 物理構成

```
[ONU] ── [LXW-10G5] ─┬─ 10G ── [自作ルーター] ── [LAN]
                     │           (eth1)         (eth2)
                     │                │
                     │           (別セグメント 1G)
                     │              (eth0)
                     │                │
                     └─ 10G ── [WXR9300BE6P]
                               (MAP-E専用)
```

- **LXW-10G5**: BUFFALO 10GbE L2スイッチ (5ポート)

### NIC構成

| VyOS名 | NIC | 速度 | 用途 |
|--------|-----|------|------|
| eth0 | オンボード | 1GbE | WXR WAN側接続 (MAP-E upstream) |
| eth1 | Intel X540-T2 Port2 | 10GbE | WAN (LXW-10G5経由でONU) |
| eth2 | Intel X540-T2 Port1 | 10GbE | LAN (主要機器向け) |
| (未使用) | RTL8126 | 5GbE | **将来eth0の代替予定** (WXR接続を5Gbpsに高速化) |

### WXR接続用別セグメント (192.168.100.x)

自作ルーターとWXR9300BE6Pを1GbEオンボードNICで直結し、IPv4転送専用の別セグメントを構築する。

- 自作ルーター側: 192.168.100.2/24
- WXR側 (LAN): 192.168.100.1/24 (DHCPサーバー無効)
- 用途: IPv4トラフィックをWXR経由でMAP-Eに転送
- 帯域: 1Gbps上限 (IPv4は例外扱いなので問題なし)

### 役割分担

| 装置 | 役割 |
|------|------|
| 自作ルーター | IPv6ルーター, RA/DHCPv6-PD取得, FW, ポリシールーティング, LANのデフォルトGW |
| WXR9300BE6P | MAP-E CE専用, IPv4 NAT, (必要なら)無線AP |

### トラフィックフロー

- **IPv6**: LAN → 自作ルーター → LXW-10G5 → ONU → NGN (10Gbps狙い)
- **IPv4**: LAN → 自作ルーター → WXR → MAP-Eトンネル (1Gbps上限)

---

## コマンド指示のルール

**重要**: コマンドを指示する際は、必ず実行先を明示すること。

- **[Mac]** - Macのターミナルで実行
- **[VyOS]** - VyOSのコンソール/SSHで実行
- **[WXR]** - WXR管理画面で操作

例:
```
[VyOS] show interfaces
[Mac] ping 192.168.1.1
```

---

## 実装順序チェックリスト

### Phase 0: VyOSインストール・基本設定
→ [docs/phase0-install.md](docs/phase0-install.md)

- [x] 0-1: VyOSインストール (2025-12-31完了)
- [x] 0-2: タイムゾーン・NTP設定 (Asia/Tokyo, ntp.nict.jp等)
- [x] 0-3: 管理者パスワード変更

### Phase 1: LAN側SSH有効化
→ [docs/phase1-ssh.md](docs/phase1-ssh.md)

- [x] 1-1: SSH有効化（LAN側 192.168.1.1 のみ）
- [x] 1-2: SSH公開鍵登録（ed25519, パスワード認証無効）

### Phase 2: IPv6基盤構築
→ [docs/phase2-ipv6.md](docs/phase2-ipv6.md)

- [x] 2-1: RA受信・DHCPv6-PD取得 (2404:7a82:4d02:4100::/56)
  - DUID-LL形式必須: `00:03:00:01:MAC`
  - 詳細は [troubleshooting-dhcpv6-pd.md](docs/troubleshooting-dhcpv6-pd.md)
- [x] 2-2: LAN側RA配布設定 (2026-01-06完了)
  - eth2で ::/64 配布
  - DNS: Cloudflare + Google
- [x] 2-3: IPv6ファイアウォール設定 (2026-01-06完了)
  - input/forward filter設定済み
  - ICMPv6, DHCPv6許可

### Phase 3: WireGuard VPN
→ [docs/phase3-wireguard.md](docs/phase3-wireguard.md)

- [ ] 3-1: WireGuard鍵生成・インターフェース作成
- [ ] 3-2: WireGuardファイアウォール許可（rate limit含む）
- [ ] 3-3: VPNアクセス制限
- [ ] 3-4: WireGuardクライアント設定

### Phase 4: WXR隔離・IPv4ルーティング
→ [docs/phase4-wxr-routing.md](docs/phase4-wxr-routing.md)

- [x] 4-1: L2スイッチ経由でWXRをONUに接続 (2026-01-06完了)
- [x] 4-2: WXR MAP-E専用化 (完了)
  - LAN側IP: 192.168.100.1
  - DHCPサーバー: 無効
  - **重要**: 「インターネット@スタートを行う」(自動判別)を使用すること。「v6プラス」手動選択は動作しない
- [x] 4-3: 別セグメント構築 (完了)
  - eth0: 192.168.100.2/24
  - NAT source rule 100 設定済み
- [x] 4-4: IPv4ルーティング設定完了 (2026-01-06)
  - デフォルトルート: 0.0.0.0/0 via 192.168.100.1
  - LAN → WXR → MAP-E → インターネット 疎通確認済み

### Phase 5: 運用設定
→ [docs/phase5-operations.md](docs/phase5-operations.md)

- [ ] 5-1: Cloudflare DDNS設定
- [ ] 5-2: ファイアウォールログ設定

### Phase 6: バックアップ体制
→ [docs/phase6-backup.md](docs/phase6-backup.md)

- [x] 6-1: VyOS設定バックアップ (完了)
  - 日次自動バックアップ: /config/scripts/backup.sh (毎日3:00)
  - 手動バックアップ: /config/backup-YYYYMMDD.txt
- [ ] 6-2: WireGuard鍵バックアップ

---

## リファレンス
→ [docs/reference.md](docs/reference.md)

- VyOS基本操作
- ルーティング方針
- ファイアウォールルール番号一覧
- 環境情報
- MAP-Eパラメータ（保険用）

---

## トラブルシューティング

- [DHCPv6-PD取得問題](docs/troubleshooting-dhcpv6-pd.md) - **解決済み** (DUID-LL形式が必須)

---

## VyOS環境の制約・注意事項

以下は実際に試行して判明した制約。同じ失敗を繰り返さないこと。

### 使えないコマンド

| コマンド | 代替手段 |
|----------|----------|
| `xxd` | `od -A x -t x1z` または `hexdump -C` |

### VyOS構文の変更 (Rolling Release)

| 旧構文 | 新構文 |
|--------|--------|
| `set system ntp server <server>` | `set service ntp server <server>` |

### DHCPv6-PD (wide-dhcpv6-client) 関連

- **DUIDファイル形式**: `/var/lib/dhcpv6/dhcp6c_duid` は先頭2バイトがリトルエンディアンの長さ
  - 例: 10バイトのDUIDなら `\x0a\x00` + DUID本体
- **DUID-LL形式**: `00:03:00:01:MAC` (NTT NGNはこの形式が必須)
- **設定ファイルの`send client-id`**: DUIDファイルより優先されるため、DUIDファイルを使う場合は`send client-id`行を削除した設定ファイルを使用

### BIGLOBE 10ギガプランの制約

- **PPPoE接続不可**: 10ギガプラン(ファミリー10ギガタイプ)ではPPPoE接続は対象外
- **IPv6オプションのみ**: IPoE + MAP-E相当の方式でのみIPv4接続可能
- **DHCPv6-PD競合**: NGNは/56を1つしか払い出さないため、VyOSとWXRで競合する

---

## ⚠️ 危険な操作と失敗事例

### カーネル更新 (2026-01-07 失敗)

**詳細**: [docs/failure-log-2026-01-07-kernel-update.md](docs/failure-log-2026-01-07-kernel-update.md)

**要約**: MODULE_SIG_FORCE=n でカーネルを再ビルドしてインストールしたが、設定が反映されておらずVyOS起動不能に。

**教訓**:
1. カーネル更新は必ずVMで事前検証
2. debパッケージのconfigを**インストール前に検証**
3. ロールバック手順を事前確認
4. 設定バックアップを必ず取得

**安全な手順**: [docs/phase6-backup.md](docs/phase6-backup.md) の「カーネル更新手順」参照

---

## 復旧用リソース

- `scripts/recovery-vyos-config.sh` - 復旧手順表示スクリプト
- `scripts/backup-vyos-config.txt` - 設定バックアップ
- [docs/phase6-backup.md](docs/phase6-backup.md) - 災害復旧手順

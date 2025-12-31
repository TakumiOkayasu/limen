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
[ONU] ── [L2 SW] ─┬─ 10G ── [自作ルーター] ── [LAN]
                  │                │
                  │           (別セグメント)
                  │                │
                  └─ 1G/2.5G ── [WXR9300BE6P]
                               (MAP-E専用)
```

### 役割分担

| 装置 | 役割 |
|------|------|
| 自作ルーター | IPv6ルーター, RA/DHCPv6-PD取得, FW, ポリシールーティング, LANのデフォルトGW |
| WXR9300BE6P | MAP-E CE専用, IPv4 NAT, (必要なら)無線AP |

### トラフィックフロー

- **IPv6**: LAN → 自作ルーター → ONU → NGN (10Gbps)
- **IPv4**: LAN → 自作ルーター → WXR → MAP-Eトンネル (1-2Gbps上限)

---

## 実装順序チェックリスト

### Phase 0: VyOSインストール・基本設定
→ [docs/phase0-install.md](docs/phase0-install.md)

- [ ] 0-1: VyOSインストール
- [ ] 0-2: タイムゾーン・NTP設定
- [ ] 0-3: 管理者パスワード変更

### Phase 1: LAN側SSH有効化
→ [docs/phase1-ssh.md](docs/phase1-ssh.md)

- [ ] 1-1: SSH有効化（LAN側のみ）
- [ ] 1-2: SSH公開鍵登録（TouchID連携）

### Phase 2: IPv6基盤構築
→ [docs/phase2-ipv6.md](docs/phase2-ipv6.md)

- [ ] 2-1: RA受信・DHCPv6-PD取得
- [ ] 2-2: LAN側RA配布設定
- [ ] 2-3: IPv6ファイアウォール設定（WAN6_IN作成）

### Phase 3: WireGuard VPN
→ [docs/phase3-wireguard.md](docs/phase3-wireguard.md)

- [ ] 3-1: WireGuard鍵生成・インターフェース作成
- [ ] 3-2: WireGuardファイアウォール許可（rate limit含む）
- [ ] 3-3: VPNアクセス制限
- [ ] 3-4: WireGuardクライアント設定

### Phase 4: WXR隔離・IPv4ルーティング
→ [docs/phase4-wxr-routing.md](docs/phase4-wxr-routing.md)

- [ ] 4-1: L2スイッチ経由でWXRをONUに接続
- [ ] 4-2: WXR MAP-E専用化
- [ ] 4-3: 別セグメント構築
- [ ] 4-4: IPv4ルーティング

### Phase 5: 運用設定
→ [docs/phase5-operations.md](docs/phase5-operations.md)

- [ ] 5-1: Cloudflare DDNS設定
- [ ] 5-2: ファイアウォールログ設定

### Phase 6: バックアップ体制
→ [docs/phase6-backup.md](docs/phase6-backup.md)

- [ ] 6-1: VyOS設定バックアップ
- [ ] 6-2: WireGuard鍵バックアップ

---

## リファレンス
→ [docs/reference.md](docs/reference.md)

- VyOS基本操作
- ルーティング方針
- ファイアウォールルール番号一覧
- 環境情報
- MAP-Eパラメータ（保険用）

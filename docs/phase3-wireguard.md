# Phase 3: WireGuard VPN

**完了日**: 2026-01-13

## タスク3-1: WireGuard鍵生成・インターフェース作成

**目的**: 外部からVPN接続できるようにする

### 3-1-1. 鍵ペア生成 (VyOS 2026.x)

VyOS 2026.x (rolling) では旧コマンド (`generate wireguard default-keypair`) は使用不可。
代わりにPKIコマンドを使用:

```bash
run generate pki wireguard key-pair
```

→ 表示された公開鍵をメモ (クライアント設定で使用)

### 3-1-2. WireGuardインターフェース作成

```bash
configure

set interfaces wireguard wg0 address 10.10.10.1/24
set interfaces wireguard wg0 address fd00:10:10:10::1/64
set interfaces wireguard wg0 port 51820
set interfaces wireguard wg0 private-key '<生成した秘密鍵>'

commit
save
```

**注意**:
- IPv6アドレスは `fd00:vpn::1` のような形式は不可 (`vpn`は16進数でない)
- `fd00:10:10:10::1/64` のように有効な16進数を使用

### 3-1-3. クライアント(peer)登録

```bash
configure

# Mac用peer
set interfaces wireguard wg0 peer mac allowed-ips 10.10.10.2/32
set interfaces wireguard wg0 peer mac allowed-ips fd00:10:10:10::2/128
set interfaces wireguard wg0 peer mac public-key '<クライアント公開鍵>'

# iPhone用peer
set interfaces wireguard wg0 peer iphone allowed-ips 10.10.10.3/32
set interfaces wireguard wg0 peer iphone allowed-ips fd00:10:10:10::3/128
set interfaces wireguard wg0 peer iphone public-key '<クライアント公開鍵>'

commit
save
```

**⚠️ 重要: allowed-ipsは必ず/32(IPv4)または/128(IPv6)で指定**
- 広いレンジ (例: 10.0.0.0/8) を指定すると、そのpeerがアドレスを偽装可能

**完了条件**: `show interfaces wireguard` でwg0が表示される ✅

---

## タスク3-2: WireGuardファイアウォール許可 (rate limit含む)

**目的**: WAN側からWireGuardのみ許可、攻撃を自動緩和

**VyOSコマンド** (新構文: firewall ipv6 input filter):
```bash
configure

# WireGuard rate limit (1分間に10回以上の新規接続をdrop)
set firewall ipv6 input filter rule 40 action drop
set firewall ipv6 input filter rule 40 protocol udp
set firewall ipv6 input filter rule 40 destination port 51820
set firewall ipv6 input filter rule 40 recent count 10
set firewall ipv6 input filter rule 40 recent time minute
set firewall ipv6 input filter rule 40 state new
set firewall ipv6 input filter rule 40 log
set firewall ipv6 input filter rule 40 description 'Rate limit WireGuard'

# WireGuard許可 (rate limitを通過したもの)
set firewall ipv6 input filter rule 50 action accept
set firewall ipv6 input filter rule 50 protocol udp
set firewall ipv6 input filter rule 50 destination port 51820
set firewall ipv6 input filter rule 50 description 'Allow WireGuard'

commit
save
```

**注意**: VyOS 2026.xでは `firewall ipv6 name WAN6_IN` (旧構文) ではなく `firewall ipv6 input filter` (新構文) を使用

**完了条件**: 外部からWireGuard接続可能 ✅

---

## タスク3-3: VPNアクセス制限

**目的**: VPNクライアントからのアクセスをVyOSのみに制限 (踏み台防止)

**VyOSコマンド** (新構文: firewall forward filter):
```bash
configure

# VPN(wg0)からLAN(eth2)への転送を禁止
set firewall ipv6 forward filter rule 90 action drop
set firewall ipv6 forward filter rule 90 inbound-interface name wg0
set firewall ipv6 forward filter rule 90 outbound-interface name eth2
set firewall ipv6 forward filter rule 90 description 'Block VPN to LAN'

# VPN(wg0)からWAN(eth1)への転送を禁止
set firewall ipv6 forward filter rule 91 action drop
set firewall ipv6 forward filter rule 91 inbound-interface name wg0
set firewall ipv6 forward filter rule 91 outbound-interface name eth1
set firewall ipv6 forward filter rule 91 description 'Block VPN to WAN'

# IPv4も同様
set firewall ipv4 forward filter default-action accept
set firewall ipv4 forward filter rule 90 action drop
set firewall ipv4 forward filter rule 90 inbound-interface name wg0
set firewall ipv4 forward filter rule 90 outbound-interface name eth2
set firewall ipv4 forward filter rule 90 description 'Block VPN to LAN'

set firewall ipv4 forward filter rule 91 action drop
set firewall ipv4 forward filter rule 91 inbound-interface name wg0
set firewall ipv4 forward filter rule 91 outbound-interface name eth1
set firewall ipv4 forward filter rule 91 description 'Block VPN to WAN'

commit
save
```

**結果**:
- VPNクライアント → VyOS (10.10.10.1 / fd00:10:10:10::1): ✅ 許可
- VPNクライアント → LAN内デバイス: ❌ 禁止
- VPNクライアント → インターネット: ❌ 禁止

**完了条件**: VPN接続後、VyOSにのみアクセス可能 ✅

---

## タスク3-4: WireGuardクライアント設定

**目的**: スマホ/PCからVPN接続できるようにする

### クライアント側の鍵生成 (Mac)

```bash
# wireguard-toolsインストール
brew install wireguard-tools

# 鍵生成
mkdir -p ~/.wireguard
wg genkey | tee ~/.wireguard/mac-private.key | wg pubkey > ~/.wireguard/mac-public.key
wg genkey | tee ~/.wireguard/iphone-private.key | wg pubkey > ~/.wireguard/iphone-public.key
```

### WireGuardクライアント設定例

**Mac用 (~/.wireguard/mac.conf)**:
```ini
[Interface]
PrivateKey = <mac-private.keyの内容>
Address = 10.10.10.2/32, fd00:10:10:10::2/128

[Peer]
PublicKey = <VyOSの公開鍵>
Endpoint = router.murata-lab.net:51820
AllowedIPs = 10.10.10.1/32, fd00:10:10:10::1/128
PersistentKeepalive = 25
```

**iPhone用 (~/.wireguard/iphone.conf)**:
```ini
[Interface]
PrivateKey = <iphone-private.keyの内容>
Address = 10.10.10.3/32, fd00:10:10:10::3/128

[Peer]
PublicKey = <VyOSの公開鍵>
Endpoint = router.murata-lab.net:51820
AllowedIPs = 10.10.10.1/32, fd00:10:10:10::1/128
PersistentKeepalive = 25
```

### 設定方法

**Mac**:
1. WireGuardアプリをインストール (`brew install --cask wireguard-go` または App Store)
2. 「ファイルからトンネルをインポート」→ `~/.wireguard/mac.conf` を選択

**iPhone**:
1. QRコード生成: `qrencode -t ansiutf8 < ~/.wireguard/iphone.conf`
2. iPhoneのWireGuardアプリで「QRコードをスキャン」

### 接続テスト

1. 外部ネットワーク (モバイル回線等) に切り替え
2. WireGuardトンネルをオン
3. `ping 10.10.10.1` で疎通確認

**完了条件**:
- [x] WireGuard接続後、VyOS (10.10.10.1) にping可能
- [x] WireGuard + SSH経由でVyOSに接続可能
- [x] スマホからWireGuard + Termius経由でSSH可能

---

## トラブルシューティング

```bash
# WireGuardインターフェース状態
show interfaces wireguard

# 接続中のpeer一覧
show wireguard peers

# ログ確認
show log | grep -i wire
show log | grep -i drop

# ファイアウォール統計
show firewall
```

### よくある問題

| 症状 | 原因 | 対処 |
|------|------|------|
| 接続できない | FWでブロック | rule 50が正しく設定されているか確認 |
| 接続後pingできない | allowed-ips不一致 | VyOS側とクライアント側の設定を確認 |
| 一定時間で切断 | NAT越え問題 | PersistentKeepalive を設定 (25秒推奨) |

---

## 現在の設定値

| 項目 | 値 |
|------|-----|
| サーバーアドレス (IPv4) | 10.10.10.1/24 |
| サーバーアドレス (IPv6) | fd00:10:10:10::1/64 |
| ポート | 51820 |
| Endpoint | router.murata-lab.net:51820 |
| Mac アドレス | 10.10.10.2 |
| iPhone アドレス | 10.10.10.3 |

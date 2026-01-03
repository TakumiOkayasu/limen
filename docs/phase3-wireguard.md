# Phase 3: WireGuard VPN

## タスク3-1: WireGuard鍵生成・インターフェース作成

**目的**: 外部からVPN接続できるようにする

### 3-1-1. 鍵ペア生成(VyOS上で実行)

```
generate wireguard default-keypair
show wireguard keypairs pubkey default
```
→ 表示された公開鍵をメモ(クライアント設定で使用)

### 3-1-2. WireGuardインターフェース作成

```
configure

set interfaces wireguard wg0 address 10.10.10.1/24
set interfaces wireguard wg0 port 51820
set interfaces wireguard wg0 private-key default
set interfaces wireguard wg0 address fd00:vpn::1/64

commit
save
```

### 3-1-3. クライアント(peer)登録

```
configure

# peer登録(クライアントごとに追加)
set interfaces wireguard wg0 peer phone allowed-ips 10.10.10.2/32
set interfaces wireguard wg0 peer phone allowed-ips fd00:vpn::2/128
set interfaces wireguard wg0 peer phone public-key <クライアント公開鍵>

# 追加クライアント例
set interfaces wireguard wg0 peer laptop allowed-ips 10.10.10.3/32
set interfaces wireguard wg0 peer laptop allowed-ips fd00:vpn::3/128
set interfaces wireguard wg0 peer laptop public-key <クライアント公開鍵>

commit
save
```

**⚠️ 重要: allowed-ipsは必ず/32(IPv4)または/128(IPv6)で指定**
- 広いレンジ（例: 10.0.0.0/8）を指定すると、そのpeerがアドレスを偽装可能

**完了条件**: `show interfaces wireguard`でwg0が表示される

---

## タスク3-2: WireGuardファイアウォール許可（rate limit含む）

**目的**: WAN側からWireGuardのみ許可、攻撃を自動緩和

**VyOSコマンド**:
```
configure

# WireGuard rate limit (1分間に10回以上の新規接続をdrop)
set firewall ipv6 name WAN6_IN rule 25 action drop
set firewall ipv6 name WAN6_IN rule 25 protocol udp
set firewall ipv6 name WAN6_IN rule 25 destination port 51820
set firewall ipv6 name WAN6_IN rule 25 recent count 10
set firewall ipv6 name WAN6_IN rule 25 recent time minute
set firewall ipv6 name WAN6_IN rule 25 state new enable
set firewall ipv6 name WAN6_IN rule 25 description 'Rate limit WireGuard'

# WireGuard許可 (rate limitを通過したもののみ)
set firewall ipv6 name WAN6_IN rule 30 action accept
set firewall ipv6 name WAN6_IN rule 30 protocol udp
set firewall ipv6 name WAN6_IN rule 30 destination port 51820
set firewall ipv6 name WAN6_IN rule 30 description 'Allow WireGuard'

commit
save
```

**完了条件**: 外部からWireGuard接続可能

---

## タスク3-3: VPNアクセス制限

**目的**: VPNクライアントからのアクセスをVyOSのみに制限（踏み台防止）

**VyOSコマンド**:
```
configure

# VPN → LAN 制限 (VyOS自身のみ許可)
set firewall ipv4 name VPN_TO_LAN default-action drop
set firewall ipv4 name VPN_TO_LAN rule 10 action accept
set firewall ipv4 name VPN_TO_LAN rule 10 destination address 10.10.10.1
set firewall ipv4 name VPN_TO_LAN rule 10 description 'Allow access to VyOS only'

set firewall ipv6 name VPN6_TO_LAN default-action drop
set firewall ipv6 name VPN6_TO_LAN rule 10 action accept
set firewall ipv6 name VPN6_TO_LAN rule 10 destination address fd00:vpn::1
set firewall ipv6 name VPN6_TO_LAN rule 10 description 'Allow access to VyOS only'

# wg0からeth2(LAN)への転送を制限
set interfaces ethernet eth2 firewall in name VPN_TO_LAN
set interfaces ethernet eth2 firewall in ipv6-name VPN6_TO_LAN

# VPN → WAN 禁止 (踏み台防止)
set firewall ipv4 name VPN_TO_WAN default-action drop
set firewall ipv4 name VPN_TO_WAN rule 1 action drop
set firewall ipv4 name VPN_TO_WAN rule 1 description 'Block VPN to Internet'

set firewall ipv6 name VPN6_TO_WAN default-action drop
set firewall ipv6 name VPN6_TO_WAN rule 1 action drop
set firewall ipv6 name VPN6_TO_WAN rule 1 description 'Block VPN to Internet'

# wg0からeth1(WAN)への転送を禁止
set interfaces ethernet eth1 firewall in name VPN_TO_WAN
set interfaces ethernet eth1 firewall in ipv6-name VPN6_TO_WAN

commit
save
```

**結果**:
- VPNクライアント → VyOS(10.10.10.1 / fd00:vpn::1): ✅ 許可
- VPNクライアント → LAN内デバイス: ❌ 禁止
- VPNクライアント → インターネット: ❌ 禁止

**完了条件**: VPN接続後、VyOSにのみアクセス可能

---

## タスク3-4: WireGuardクライアント設定

**目的**: スマホ/PCからVPN接続できるようにする

### WireGuardクライアント設定例

```ini
[Interface]
PrivateKey = <クライアント秘密鍵>
Address = 10.10.10.2/32, fd00:vpn::2/128

[Peer]
PublicKey = <VyOSの公開鍵(タスク3-1でメモしたもの)>
Endpoint = router.your-domain.com:51820
AllowedIPs = 10.10.10.1/32, fd00:vpn::1/128
PersistentKeepalive = 25
```

**⚠️ AllowedIPsについて**:
- `10.10.10.1/32, fd00:vpn::1/128`: VyOSのみにアクセス（推奨）
- タスク3-3でLAN/インターネットへの転送を禁止しているため、VyOS以外は到達不可

### クライアント側の鍵生成

**事前生成済みの鍵を使用する場合** (推奨):
```bash
# Mac/Linuxで事前生成した鍵
~/.wireguard/client-private.key  # クライアント設定のPrivateKeyに使用
~/.wireguard/client-public.key   # VyOS側のpeer登録に使用
```

**新規生成する場合**:
- iOS/Android: WireGuardアプリで「鍵ペアを生成」
- Mac/Linux: `wg genkey | tee privatekey | wg pubkey > publickey`
- Windows: WireGuardアプリで「空のトンネルを追加」→自動生成

### スマホからのSSHアクセス（Termius）

1. Termiusをインストール
2. アプリ内で鍵ペアを生成（Settings → Keychain → Generate Key）
3. 生成した公開鍵をVyOSに登録（タスク1-2-3と同様）
4. 新規ホストを追加（Hostname: `10.10.10.1`, Username: `vyos`）
5. WireGuard接続後、Termiusから接続
6. Face ID/Touch IDを有効化 → アプリ起動時に生体認証

**完了条件**:
- [ ] WireGuard接続後、VyOS(10.10.10.1)にping可能
- [ ] WireGuard + SSH経由でVyOSに接続可能
- [ ] スマホからWireGuard + Termius経由でSSH可能

### トラブルシューティング

```bash
# WireGuardインターフェース状態
show interfaces wireguard

# 接続中のpeer一覧
show wireguard peers

# ログ確認
show log | grep -i wire
show log | grep -i drop

# ファイアウォールでブロックされていないか
show firewall statistics
```

### よくある問題

| 症状 | 原因 | 対処 |
|------|------|------|
| 接続できない | FWでブロック | rule 30が正しく設定されているか確認 |
| 接続後pingできない | allowed-ips不一致 | VyOS側とクライアント側の設定を確認 |
| 一定時間で切断 | NAT越え問題 | PersistentKeepalive を設定(25秒推奨) |

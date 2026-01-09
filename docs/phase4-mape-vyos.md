# Phase 4: VyOSでMAP-E実装

## 概要

VyOS自身がMAP-E CE (Customer Edge) となり、IPv4インターネット接続を提供する。

### 構成図

```
[ONU] ── [LXW-10G5] ─── 10G ── [VyOS] ── 10G ── [LAN]
                               (eth1)           (eth2)
                                 │
                            MAP-E CE
                            (IPIP6トンネル)
                                 │
                               [WXR]
                               (APモード, WiFiのみ)
```

### メリット

- 10GbE回線を100%活用
- VyOS一台で完結
- WXRはAP専用で単純化

### 制約

- 16ポート制限 (5136-5151)
- プレフィックス変更時は手動再設定

---

## MAP-Eパラメータ

BIGLOBE v6プラス (JPNE) の設定値:

| パラメータ | 値 |
|------------|-----|
| CE IPv6 | `2404:7a82:4d02:4100:85:d10d:200:4100` |
| BR IPv6 | `2001:260:700:1::1:275` |
| IPv4アドレス | `133.209.13.2` |
| ポート範囲 | `5136-5151` (16ポート) |
| PSID | 計算による |

**注意**: DHCPv6-PDで取得するプレフィックスが変わるとCE IPv6も変わる。その場合は再計算・再設定が必要。

---

## 実装手順

### 事前準備: 復旧用設定のバックアップ

```bash
# [VyOS] 現在の設定をバックアップ
show configuration commands > /config/backup-before-mape.txt
```

### Step 1: IPIP6トンネル作成

```bash
# [VyOS]
configure

# MAP-Eトンネルインターフェース作成
set interfaces tunnel tun0 encapsulation 'ipip6'
set interfaces tunnel tun0 source-address '2404:7a82:4d02:4100:85:d10d:200:4100'
set interfaces tunnel tun0 remote '2001:260:700:1::1:275'
set interfaces tunnel tun0 address '133.209.13.2/32'
set interfaces tunnel tun0 mtu '1460'

commit
```

### Step 2: IPv4デフォルトルート設定

```bash
# [VyOS]
# トンネル経由でIPv4インターネットへ
set protocols static route 0.0.0.0/0 interface tun0

commit
```

### Step 3: ポート制限NAT (nftables)

VyOSのNAT設定ではポート範囲制限ができないため、nftablesを直接使用。

```bash
# [VyOS] nftablesルール作成
sudo nft add table ip nat
sudo nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; }
sudo nft add rule ip nat postrouting oifname "tun0" snat to 133.209.13.2:5136-5151
```

### Step 4: 永続化スクリプト作成

```bash
# [VyOS] スクリプト作成
sudo tee /config/scripts/mape-nat.sh << 'EOF'
#!/bin/bash
# MAP-E NAT設定 (ポート制限)
nft add table ip nat 2>/dev/null || true
nft add chain ip nat postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true
nft flush chain ip nat postrouting
nft add rule ip nat postrouting oifname "tun0" snat to 133.209.13.2:5136-5151
EOF

sudo chmod +x /config/scripts/mape-nat.sh
```

### Step 5: 起動時自動実行

```bash
# [VyOS]
configure
set system task-scheduler task mape-nat crontab-spec '@reboot'
set system task-scheduler task mape-nat executable path '/config/scripts/mape-nat.sh'
commit
save
```

### Step 6: 動作確認

```bash
# [VyOS]
# トンネル状態確認
show interfaces tunnel tun0

# IPv4ルート確認
show ip route

# IPv4疎通テスト
ping 8.8.8.8 -c 3

# NAT確認
sudo nft list table ip nat
```

---

## トラブルシューティング

### ping が通らない場合

1. トンネルインターフェース確認:
   ```bash
   ip -6 tunnel show
   ip addr show tun0
   ```

2. ルーティング確認:
   ```bash
   ip route get 8.8.8.8
   ```

3. CE IPv6アドレスが正しいか確認:
   ```bash
   # DHCPv6-PDで取得したプレフィックスから計算
   show interfaces ethernet eth1
   ```

### NAT が動作しない場合

1. nftablesルール確認:
   ```bash
   sudo nft list ruleset
   ```

2. conntrack確認:
   ```bash
   sudo conntrack -L
   ```

---

## 復旧手順

MAP-Eが動作しない場合、元の状態に戻す:

```bash
# [VyOS]
configure

# トンネル削除
delete interfaces tunnel tun0
delete protocols static route 0.0.0.0/0 interface tun0

# タスクスケジューラ削除
delete system task-scheduler task mape-nat

commit
save

# nftablesクリア
sudo nft flush table ip nat
sudo nft delete table ip nat
```

---

## 代替案: WXRへのプレフィックス再委譲 (案H)

MAP-Eが複雑すぎる場合、VyOSからWXRにDHCPv6-PDでプレフィックスを再委譲する方法も検討可能。

### 概念

```
NGN → VyOS (/56取得) → WXR (/60委譲) → MAP-E動作
```

### 実装案

```bash
# [VyOS] DHCPv6サーバーでPD委譲
set service dhcpv6-server shared-network-name WXR subnet 2404:7a82:4d02:4100::/56 prefix-delegation start 2404:7a82:4d02:4110::/60 stop 2404:7a82:4d02:411f::/60 prefix-length 60
```

**注意**: WXRがLAN側でDHCPv6-PDクライアントとして動作するか要検証。

---

## プレフィックス変更時の対応

DHCPv6-PDで取得するプレフィックスが変わった場合:

1. 新しいプレフィックスを確認:
   ```bash
   show interfaces ethernet eth1
   ```

2. MAP-Eパラメータを再計算 (JPNEのルールに従う)

3. トンネル設定を更新:
   ```bash
   configure
   set interfaces tunnel tun0 source-address '<新しいCE IPv6>'
   commit
   save
   ```

4. 必要に応じてNATルールも更新

---

## 参考資料

- [VyOS Tunnel Documentation](https://docs.vyos.io/en/latest/configuration/interfaces/tunnel.html)
- [MAP-E RFC 7597](https://tools.ietf.org/html/rfc7597)
- [v6プラス技術仕様](https://www.jpne.co.jp/service/v6plus/)

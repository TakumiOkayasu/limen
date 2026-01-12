# MAP-E トンネル設定ドキュメント (2026-01-12 更新)

## 概要

VyOSから直接MAP-Eトンネルを使用してIPv4インターネットに接続する設定。
VyOSネイティブ設定 (`set interfaces tunnel tun0`) を使用。

## 物理構成

```
ONU ─── 10G ─── VyOS eth1 (WAN)
                    │
               VyOS eth2 (LAN) ─── LXW-10G5 ───┬─── Mac/PC
                                               └─── WXR (APモード)
```

**重要**: WXRは**APモード**で運用すること。ルーターモードではNGNと競合する。

## MAP-Eパラメータ

| パラメータ | 値 |
|-----------|-----|
| CE Address | 2404:7a82:4d02:4100:85:d10d:200:4100 |
| BR (東日本) | 2001:260:700:1::1:275 |
| IPv4 Address | 133.209.13.2 |
| Port Range | 5136-5151 |
| NGN Gateway | fe80::a611:bbff:fe7d:ee11 |

## 設定手順 (最短ルート)

### 前提条件

1. WXRがAPモードであること (ルーターモードは競合する)
2. eth1がONUに接続されていること
3. DUID-LLが設定済みであること

### Step 1: 起動スクリプト (DUID-LL設定)

```bash
sudo tee /config/scripts/vyos-preconfig-bootup.script << 'EOF'
#!/bin/sh
# DHCPv6 DUID-LL形式を強制設定 (NGN対応)
mkdir -p /var/lib/dhcpv6
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' > /var/lib/dhcpv6/dhcp6c_duid
EOF
sudo chmod +x /config/scripts/vyos-preconfig-bootup.script
```

### Step 2: VyOS設定

```bash
configure

# eth1にCEアドレスを追加
set interfaces ethernet eth1 address '2404:7a82:4d02:4100:85:d10d:200:4100/64'

# BRへの静的ルート
set protocols static route6 2001:260:700:1::1:275/128 next-hop fe80::a611:bbff:fe7d:ee11 interface 'eth1'

# MAP-Eトンネル (VyOSネイティブ設定)
set interfaces tunnel tun0 encapsulation ipip6
set interfaces tunnel tun0 source-address 2404:7a82:4d02:4100:85:d10d:200:4100
set interfaces tunnel tun0 remote 2001:260:700:1::1:275
set interfaces tunnel tun0 source-interface eth1
set interfaces tunnel tun0 address 133.209.13.2/32

# デフォルトルート
set protocols static route 0.0.0.0/0 interface tun0

# NAT (ポート範囲制限) - source addressは指定しない
set nat source rule 200 outbound-interface name 'tun0'
set nat source rule 200 protocol tcp_udp
set nat source rule 200 translation address '133.209.13.2'
set nat source rule 200 translation port '5136-5151'

commit
save
```

## 動作確認

```bash
# IPv4疎通確認 (pingはMAP-Eで動作しない)
curl -4 -I https://www.google.com

# トンネル状態
ip link show tun0
ip -d link show tun0

# ルート確認
ip route show default

# パケット確認
sudo tcpdump -i eth1 -n 'ip6 and host 2001:260:700:1::1:275' -c 5
```

## トラブルシューティング

### curlがタイムアウトする

1. **WXRがルーターモードになっていないか確認**
   - ルーターモードだとNGNと競合する
   - APモードに変更すること

2. **NGNゲートウェイへのpingを確認**
   ```bash
   ping fe80::a611:bbff:fe7d:ee11%eth1 count 2
   ```
   - 失敗する場合、物理接続またはWXR競合を疑う

3. **NATルールを確認**
   ```bash
   sudo nft list ruleset | grep -A 5 "SRC-NAT-200"
   ```
   - `source address` が指定されていないことを確認
   - 指定されていると、VyOS自身からの通信がNATされない

### よくある間違い

| 間違い | 正しい設定 |
|--------|-----------|
| NATに `source address 192.168.1.0/24` を指定 | source addressは指定しない |
| WXRをルーターモードで運用 | APモードにする |
| 手動 `ip -6 tunnel add mape` を使用 | VyOS設定 `set interfaces tunnel tun0` を使用 |

## 注意事項

- **pingは動作しない**: MAP-Eのポート制限によりICMPは使用不可。curlで確認。
- **ポート範囲**: 5136-5151 (16ポート) のみ使用可能

## 関連ドキュメント

- [reference.md](reference.md) - 環境情報、MACアドレス一覧
- [troubleshooting-dhcpv6-pd.md](troubleshooting-dhcpv6-pd.md) - DUID-LL設定詳細

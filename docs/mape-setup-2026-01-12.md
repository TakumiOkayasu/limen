# MAP-E トンネル設定ドキュメント (2026-01-12)

## 概要

VyOSからWXRを経由せず、直接MAP-Eトンネルを使用してIPv4インターネットに接続する設定。

## 現在の状態

| 項目 | 値 |
|------|-----|
| IPv4経路 | VyOS → MAP-Eトンネル → BR → インターネット |
| IPv6経路 | VyOS → NGN → インターネット |
| WXR | 未使用 (バックアップとして維持) |

## MAP-Eパラメータ

| パラメータ | 値 |
|-----------|-----|
| CE Address | 2404:7a82:4d02:4100:85:d10d:200:4100 |
| BR (東日本) | 2001:260:700:1::1:275 |
| IPv4 Address | 133.209.13.2 |
| Port Range | 5136-5151 (16ポート x 15ブロック = 240ポート) |

## 設定ファイル

### /config/scripts/vyos-preconfig-bootup.script

```bash
#!/bin/sh
# This script is executed at boot time before VyOS configuration is applied.

# DHCPv6 DUID-LL形式を強制設定 (NGN対応)
mkdir -p /var/lib/dhcpv6
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' > /var/lib/dhcpv6/dhcp6c_duid

# MAP-Eトンネル設定
ip -6 tunnel add mape mode ip4ip6 remote 2001:260:700:1::1:275 local 2404:7a82:4d02:4100:85:d10d:200:4100 dev eth1
ip addr add 133.209.13.2/32 dev mape
ip link set mape up
ip route add default dev mape
```

### VyOS設定 (関連部分)

```bash
# eth1にCEアドレスを追加 (トンネルのsource-addressとして必要)
set interfaces ethernet eth1 address '2404:7a82:4d02:4100:85:d10d:200:4100/64'

# BRへのルート
set protocols static route6 2001:260:700:1::1:275/128 next-hop fe80::a611:bbff:fe7d:ee11 interface 'eth1'

# NAT (SNAT) - ポート範囲制限
set nat source rule 200 outbound-interface name 'tun0'
set nat source rule 200 translation address '133.209.13.2'
set nat source rule 200 translation port '5136-5151'
set nat source rule 200 protocol 'tcp_udp'
```

## 動作確認コマンド

```bash
# IPv4疎通確認 (pingはMAP-Eで動作しないためcurlを使用)
curl -4 -I https://www.google.com

# トンネル状態確認
ip link show mape
ip -s link show mape

# ルート確認
ip route show default

# トンネル経由のパケット確認
sudo tcpdump -i eth1 -n 'ip6 and host 2001:260:700:1::1:275' -c 10
```

## 切り戻し手順 (WXR経由に戻す)

### 一時的な切り戻し (再起動で元に戻る)

```bash
# mapeトンネルを削除
sudo ip link del mape

# WXR経由のデフォルトルートを追加
sudo ip route add default via 192.168.100.1
```

### 恒久的な切り戻し

1. スクリプトのMAP-E部分をコメントアウト:
```bash
sudo nano /config/scripts/vyos-preconfig-bootup.script
# → MAP-E関連の行の先頭に # を追加
```

2. VyOS設定でWXR経由のルートを追加:
```bash
configure
set protocols static route 0.0.0.0/0 next-hop 192.168.100.1
commit
save
```

3. 再起動:
```bash
sudo reboot
```

## 注意事項

### pingが動作しない理由

MAP-Eではポート範囲が制限されているため、ICMPは正常に動作しません。IPv4疎通確認にはcurlやwgetを使用してください。

### VyOSネイティブ設定が動作しない問題

VyOSの `set interfaces tunnel tunX` 設定では、トンネル経由のパケットが送信されない問題があります。原因は調査中。現在は起動スクリプトで手動コマンドを実行するワークアラウンドを使用しています。

## 関連ドキュメント

- [docs/reference.md](reference.md) - MAP-Eパラメータ、MACアドレス一覧
- [docs/troubleshooting-dhcpv6-pd.md](troubleshooting-dhcpv6-pd.md) - DUID-LL設定
- [docs/work-log-2026-01-11.md](work-log-2026-01-11.md) - MAP-E試行ログ

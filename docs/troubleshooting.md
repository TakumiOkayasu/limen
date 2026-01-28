# トラブルシューティングガイド

VyOSルーター環境のトラブルシューティング総合ガイド。

---

## 目次

1. [IPv6接続問題](#1-ipv6接続問題)
2. [MAP-E (IPv4) 接続問題](#2-map-e-ipv4-接続問題)
   - [2.5 HTTPS/TLSが特定サイトでタイムアウト](#25-httpstlsが特定サイトでタイムアウト)
3. [ネットワークセグメント・DHCP問題](#3-ネットワークセグメントdhcp問題)

---

## 1. IPv6接続問題

### 1.1 IPv6で外部に繋がらない (LAN側クライアント)

**症状**: `curl -6 https://ifconfig.co` がタイムアウト

**最も可能性が高い原因**: **WANとLANで同じ/64プレフィックスを使用している**

#### 確認手順

```bash
[VyOS] ip -6 route show | grep "/64"
```

**問題のある出力例**:
```
<prefix>::/64 dev eth2 proto kernel metric 256
<prefix>::/64 dev eth1 proto kernel metric 256  # 重複！
```

同じプレフィックスがeth1 (WAN) とeth2 (LAN) の両方にある場合、戻りパケットが正しいインターフェースに届かない。

#### 解決方法

**LANには/56の別の/64サブネットを使用する**:

```bash
[VyOS] configure

# 例: WANが4100を使っている場合、LANは4101を使用
delete service router-advert interface eth2 prefix <old-prefix>::/64
set service router-advert interface eth2 prefix <new-prefix>::/64
set interfaces ethernet eth2 address <new-prefix>::1/64

commit
save
```

---

### 1.2 RAが配布されない

**症状**: クライアントがIPv6アドレスを取得できない

**確認手順**:

```bash
[VyOS] show configuration commands | grep router-advert
[VyOS] ps aux | grep radvd
```

---

### 1.3 IPv6 DNS解決できない

**症状**: IPv6アドレスは取得できるが、名前解決ができない

**対処**: RAでRDNSSを配布:

```bash
[VyOS] set service router-advert interface eth2 name-server 2606:4700:4700::1111
[VyOS] set service router-advert interface eth2 name-server 2001:4860:4860::8888
```

---

## 2. MAP-E (IPv4) 接続問題

### 2.1 IPv4に繋がらなくなった

**症状**: 突然IPv4インターネット接続ができなくなった

**最も可能性が高い原因**: **DHCPv6-PDプレフィックスの変更**

#### 確認手順

```bash
[VyOS] show interfaces ethernet eth1
```

現在のIPv6アドレスを確認し、MAP-E設定のプレフィックスと比較。

#### 対処

1. MAP-Eパラメータを再計算
2. 設定を更新
3. トンネル再作成

---

### 2.2 pingが通らない

**症状**: `ping 8.8.8.8` がタイムアウト

**原因**: **MAP-Eの仕様 (正常動作)**

MAP-Eではポート範囲が制限されているため、ICMPは動作しない。

**確認方法**: curlを使用

```bash
[VyOS] curl -4 -I https://www.google.com
```

200/301/302が返れば正常。

---

### 2.3 ポート枯渇

**症状**: 一部のサイトのみ接続できない、接続が不安定

**原因**: MAP-Eの同時接続数制限

#### 確認

```bash
[VyOS] sudo conntrack -L | wc -l
```

#### 対処

MAP-EのNATルールで全ポートブロックを使用しているか確認:

```bash
[VyOS] sudo nft list table ip vyos_nat | grep snat
```

16ポートのみ (1ブロック) しか設定されていない場合、全15ブロック (240ポート) を設定する。

---

### 2.4 戻りパケットが来ない

**症状**: tcpdumpで送信は確認できるが応答がない

**原因候補**:

1. **rp_filter (Reverse Path Filter)**

   ```bash
   [VyOS] cat /proc/sys/net/ipv4/conf/all/rp_filter
   # 2でなければ緩和
   [VyOS] sudo sh -c 'echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter'
   ```

2. **BRアドレスの非対称性**: `remote any` でトンネル再作成

---

### 2.5 HTTPS/TLSが特定サイトでタイムアウト

**症状**: HTTPS接続が特定サイト（例: github.com）でタイムアウトするが、SSH（port 22）は正常

**原因**: **MSS Clamp policy routeがLAN側インターフェースに未適用**

MAP-Eトンネルのカプセル化によりMTUが小さくなるが、LAN側でMSS調整が行われないとTLSハンドシェイクの大きなパケットがトンネルMTUを超過する。ICMPがブロックされている環境ではPMTUDも機能せず、タイムアウトとなる。

#### 確認手順

```bash
# MSS-CLAMP policy routeの適用状況を確認
[VyOS] show configuration commands | grep MSS-CLAMP

# eth2 (LAN) に適用されているか？
# 以下が出力に含まれていなければ未適用
# set policy route MSS-CLAMP interface eth2
```

#### 解決方法

**恒久対応**:

```bash
[VyOS] configure
[VyOS] set policy route MSS-CLAMP interface eth2
[VyOS] commit
[VyOS] save
```

**検証**:

```bash
[Mac] curl -I https://github.com
# 200 OK が返れば正常
```

詳細な診断記録: [GitHub接続遅延 調査レポート](github-connection-diagnosis.md)

---

## 3. ネットワークセグメント・DHCP問題

### 3.1 クライアントが間違ったセグメントのIPを取得する

**症状**: クライアントが想定外のIPアドレス (例: 192.168.100.x) を取得し、インターネットに接続できない

#### 確認手順

1. クライアントのIPアドレス確認
   ```bash
   [Windows] ipconfig
   [Linux/Mac] ip a
   ```

2. VyOSのDHCPサーバー設定確認
   ```bash
   [VyOS] show configuration commands | grep dhcp
   ```

#### よくある原因

**不要なDHCPサーバー設定が残っている**

```bash
# 問題のある設定例
set service dhcp-server shared-network-name OLD_SEGMENT subnet 192.168.100.0/24 ...
```

構成変更後に古いDHCPサーバー設定が残っていると、意図しないセグメントにIPを配布してしまう。

#### 解決方法

```bash
[VyOS] configure
[VyOS] delete service dhcp-server shared-network-name <不要なネットワーク名>
[VyOS] commit
[VyOS] save
```

クライアント側でDHCPリース更新:
```bash
[Windows] ipconfig /release && ipconfig /renew
[Linux] sudo dhclient -r && sudo dhclient
```

---

### 3.2 APモードのWXRに接続したデバイスがインターネットに出られない

**症状**: WXRのLANポートまたはWi-Fiに接続したデバイスがインターネット接続できない

#### 確認事項

1. **WXRのIPアドレス設定**: VyOS LANと同じセグメントか？
   - 正: WXR IP = 192.168.1.x (VyOS LANセグメント)
   - 誤: WXR IP = 192.168.100.x (別セグメント)

2. **VyOSのDHCPサーバー**: 正しいセグメントのみ配布しているか？

3. **物理接続**: WXR WANポートがVyOS LAN側に接続されているか？

#### 解決方法

1. WXRのLAN側IPをVyOS LANセグメントに変更:
   ```
   IPアドレス: 192.168.1.2
   サブネット: 255.255.255.0
   デフォルトGW: 192.168.1.1 (VyOS)
   ```

2. 不要なDHCPサーバー設定を削除 (上記3.1参照)

---

## デバッグコマンド集

### ARPテーブル

```bash
[VyOS] show arp
[VyOS] ip neigh show
```

### ルーティング

```bash
[VyOS] ip route show
[VyOS] ip -6 route show
```

### DHCP

```bash
[VyOS] show dhcp server leases
[VyOS] show configuration commands | grep dhcp
```

### NAT

```bash
[VyOS] sudo nft list table ip vyos_nat
[VyOS] sudo conntrack -L
```

### パケットキャプチャ

```bash
[VyOS] sudo tcpdump -i eth1 -n
[VyOS] sudo tcpdump -i eth2 -n
[VyOS] sudo tcpdump -i mape -n
```

---

## 関連ドキュメント

- [CLAUDE.md](../CLAUDE.md) - プロジェクト概要
- [scripts/setup-mape.sh](../scripts/setup-mape.sh) - MAP-Eセットアップスクリプト

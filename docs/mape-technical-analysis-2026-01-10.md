# MAP-E技術分析レポート (2026-01-10)

## 調査目的

昨日 (2026-01-09) のMAP-E実装作業で発生した問題の根本原因を特定し、解決策を整理する。

---

## DS-Lite vs MAP-E の違い (重要)

| 項目 | DS-Lite | MAP-E |
|------|---------|-------|
| NAT処理場所 | **ISP側 (AFTR)** | **ユーザー側 (CE)** |
| CPE側の名称 | B4 | CE |
| 収容装置側の名称 | AFTR | BR |
| グローバルIPv4 | 事業者側に存在 | ユーザー側ルーターに割当 |
| VyOS設定の複雑さ | 簡単 (NATなし) | 複雑 (NAPT必須) |

**MAP-Eの難しさ**: CE側でNAPTを行う必要があり、かつ**許可されたポート範囲内**でのみ変換が必要。

---

## 問題の整理

### 昨日の状況

1. MAP-Eトンネル (ip6tnl) を作成 → UP
2. パケット送信: eth1からBRへ正しく送信されている (tcpdump確認) ✓
3. **戻りパケットが一切来ない** ✗

### 昨日考えられた原因

1. BR側で認証されていない可能性
2. BRアドレスの非対称性 (送信先と応答元が異なる)
3. ポート範囲の問題 (16ポートのみ設定)

---

## 調査結果

### 1. BRアドレスの確認

| 用途 | アドレス | 備考 |
|------|---------|------|
| BR (送信先) | `2404:9200:225:100::64` | JPNE/BIGLOBE共通、正しい |
| 応答元 (以前の調査) | `2001:260:700:1::1:275` | **東日本向けBR** |

**発見**: BIGLOBEには複数のBRアドレスが存在する

- **DMR (Default Mapping Rule)**: `2404:9200:225:100::64` - api.enabler.ne.jp から取得
- **東日本BR**: `2001:260:700:1::1:275` (東京)
- **西日本BR**: `2001:260:700:1::1:276` (大阪)

これが「送信先と応答元が異なる」問題の原因の可能性が高い。

### 2. ip6tnl の remote any について

[Red Hat Developer - Linux Virtual Interfaces: Tunnels](https://developers.redhat.com/blog/2019/05/17/an-introduction-to-linux-virtual-interfaces-tunnels) より:

> ip6tnl0 はデフォルトデバイスとして作成され、`local=any` と `remote=any` の属性を持つ。
> IPIP プロトコルパケットを受信すると、カーネルは local/remote 属性が一致するデバイスを探し、
> 見つからない場合は **フォールバックデバイスとして ip6tnl0 に転送する**。

**問題点**:
- ip6tnl0 のデフォルトモードは `ipv6` (IPv6 over IPv6)
- MAP-E に必要な `ipip6` (IPv4 over IPv6) モードではない
- モードは**ランタイムで変更不可**

[systemd issue #34930](https://github.com/systemd/systemd/issues/34930) より:
> systemd-networkd で `Local=any` `Remote=any` を設定すると無視される

### 3. OpenWrt map.sh の解決策

[fakemanhk/openwrt-jp-ipoe](https://github.com/fakemanhk/openwrt-jp-ipoe) の修正版 map.sh:

- **問題**: 標準の map.sh は16ポート (1ブロック) のみ使用
- **解決**: 15ブロック全て (240ポート) を使用するよう修正
- **重要**: ポートセットを均等に分散させるiptablesルールが必要

---

## 技術的解決策

### 解決策A: remote any でトンネル再作成

```bash
[VyOS] sudo ip -6 tunnel del mape
[VyOS] sudo ip -6 tunnel add mape mode ip4ip6 \
    remote any \
    local 2404:7a82:4d02:4100:85:d10d:200:4100 \
    dev eth1
[VyOS] sudo ip addr add 133.209.13.2/32 dev mape
[VyOS] sudo ip link set mape up
[VyOS] sudo ip route add default dev mape
```

**期待効果**: 任意のアドレスからの応答パケットを受信可能

**リスク**: VyOSのip6tnlがremote anyをサポートしているか不明

### 解決策B: ip6tnl0 フォールバックデバイスの活用

```bash
# ip6tnl0 を any モードで再設定 (要検証)
[VyOS] sudo ip link set ip6tnl0 down
[VyOS] sudo ip -6 tunnel change ip6tnl0 mode any
[VyOS] sudo ip link set ip6tnl0 up
```

**問題**: ip6tnl0 のモードはランタイムで変更できない可能性あり

### 解決策C: 両方のBRアドレスへのルーティング

```bash
# 東日本BR からの応答も受け付けるルート追加
[VyOS] sudo ip -6 route add 2001:260:700:1::1:275/128 via fe80::a611:bbff:fe7d:ee11 dev eth1
```

**問題**: トンネルは特定のremoteアドレスにバインドされているため、
別アドレスからのパケットは処理されない

### 解決策D: 複数トンネルの作成

```bash
# DMR用トンネル
[VyOS] sudo ip -6 tunnel add mape-dmr mode ip4ip6 \
    remote 2404:9200:225:100::64 \
    local 2404:7a82:4d02:4100:85:d10d:200:4100 \
    dev eth1

# 東日本BR用トンネル
[VyOS] sudo ip -6 tunnel add mape-east mode ip4ip6 \
    remote 2001:260:700:1::1:275 \
    local 2404:7a82:4d02:4100:85:d10d:200:4100 \
    dev eth1
```

**問題**: どちらに送信するか、どちらから受信するかのルーティングが複雑

---

## 根本的な問題の考察

### なぜWXRでは動くがVyOSでは動かないのか

| 項目 | WXR | VyOS |
|------|-----|------|
| MAP-Eパラメータ | DHCPv6 S46オプションで自動取得 | 手動設定 |
| BR認証 | ISP/JPNE側で自動認証 | 認証なし? |
| トンネル処理 | 専用実装 (複数BR対応?) | 標準 ip6tnl |
| NAPT | 240ポート全て自動設定 | 16ポートのみ手動設定 |

**仮説**:
1. BIGLOBEのMAP-E BRは、DHCPv6でS46オプションを正しく取得したクライアントのみ認証している
2. または、送信先と応答元のBRが異なるルーティング構成になっている

### DHCPv6 S46オプションの重要性

RFC 7598 で定義された MAP-E 用 DHCPv6 オプション:
- Option 94 (S46_RULE): MAP ルール
- Option 95 (S46_BR): BR アドレス
- Option 96 (S46_DMR): DMR プレフィックス

**VyOSの wide-dhcpv6 は S46 オプションをサポートしていない可能性が高い**

---

## 次回試すべきアクション (優先順位順)

### 1. remote any でトンネル再作成 (最優先)

最も簡単な修正。応答アドレスが異なる問題を解決できる可能性。

### 2. tcpdump で詳細解析

```bash
# BR宛の送信パケット
[VyOS] sudo tcpdump -i eth1 -n 'ip6 and host 2404:9200:225:100::64'

# 東日本BRからの応答確認
[VyOS] sudo tcpdump -i eth1 -n 'ip6 and host 2001:260:700:1::1:275'

# すべての ip4ip6 パケット
[VyOS] sudo tcpdump -i eth1 -n 'ip6 proto 4'
```

### 3. 全ポート範囲のNAPT設定

現在16ポートのみ。15ブロック分のルールを追加:

```bash
[VyOS] # configure モードで
set nat source rule 201 outbound-interface name 'mape'
set nat source rule 201 source address '192.168.1.0/24'
set nat source rule 201 protocol 'tcp_udp'
set nat source rule 201 translation address '133.209.13.2'
set nat source rule 201 translation port '9232-9247'
# ... rule 214 まで繰り返し
```

### 4. WXRのMAP-E設定を再度取得

WXRがMAP-E接続に成功している状態で:
- 管理画面からMAP-Eステータスを確認
- 使用しているBRアドレスを特定
- NAPT設定を確認

---

## 代替案: WXR経由に戻す

MAP-E実装が困難な場合、Phase 4-4 で確認済みの構成に戻す:

- IPv6: VyOS → LXW-10G5 → ONU → NGN (10Gbps)
- IPv4: VyOS → WXR → MAP-E → インターネット (1Gbps上限)

**メリット**: 既に動作実績あり
**デメリット**: IPv4は1Gbps上限

---

## 新発見: rp_filter (Reverse Path Filter) の問題

[Red Hat - Asymmetric Routing](https://access.redhat.com/solutions/53031) より:

> Strict filtering means that when a packet arrives on the system, the kernel takes the source IP
> of the packet and makes a lookup of its routing table to see if the interface the packet arrived
> on is the same interface the kernel would use to send a packet to that IP.

**VyOSのデフォルト設定がstrict modeの場合**、異なるBRアドレスからの応答パケットが破棄される可能性がある。

### 確認・設定方法

```bash
# 現在の設定確認
[VyOS] cat /proc/sys/net/ipv4/conf/all/rp_filter
[VyOS] cat /proc/sys/net/ipv4/conf/eth1/rp_filter

# VyOS設定で緩和 (loose mode)
[VyOS] set interfaces ethernet eth1 ip source-validation loose
# または
[VyOS] set interfaces tunnel tun0 ip source-validation loose
```

---

## 新発見: userland-ipip の存在

[m13253/userland-ipip](https://github.com/m13253/userland-ipip):

> "type ip6tnl mode any tunnel is not as reliable as you assume.
> Either IPv4 or IPv6 payload drops silently"

カーネルのip6tnlに信頼性問題がある場合、ユーザーランド実装が選択肢になる。

---

## 新発見: VyOSネイティブのトンネル設定

VyOSはipip6トンネルをネイティブサポートしている:

```bash
[VyOS] set interfaces tunnel tun0 encapsulation ipip6
[VyOS] set interfaces tunnel tun0 source-address 2404:7a82:4d02:4100:85:d10d:200:4100
[VyOS] set interfaces tunnel tun0 remote 2404:9200:225:100::64
[VyOS] set interfaces tunnel tun0 address 133.209.13.2/32
```

**問題**: VyOSの `remote` パラメータは具体的なアドレスが必要。`any` は指定できない可能性。

---

## 修正版アクションリスト

### 次回VyOS接続時に試すこと (優先順)

#### 1. rp_filter設定の確認・緩和 (最優先)

```bash
# 確認
[VyOS] cat /proc/sys/net/ipv4/conf/all/rp_filter
[VyOS] cat /proc/sys/net/ipv4/conf/eth1/rp_filter

# loose mode に変更
[VyOS] configure
[VyOS] set interfaces ethernet eth1 ip source-validation loose
[VyOS] commit
```

#### 2. remote any でトンネル再作成

```bash
[VyOS] sudo ip -6 tunnel del mape
[VyOS] sudo ip -6 tunnel add mape mode ip4ip6 \
    remote any \
    local 2404:7a82:4d02:4100:85:d10d:200:4100 \
    dev eth1
[VyOS] sudo ip addr add 133.209.13.2/32 dev mape
[VyOS] sudo ip link set mape up
[VyOS] sudo ip route add default dev mape
```

#### 3. 東日本BRからの応答をtcpdumpで確認

```bash
# 全てのip4ip6パケット
[VyOS] sudo tcpdump -i eth1 -n 'ip6 proto 4'

# 東日本BRからの応答確認
[VyOS] sudo tcpdump -i eth1 -n 'ip6 and host 2001:260:700:1::1:275'
```

#### 4. VyOSネイティブ設定を試す

```bash
[VyOS] configure
[VyOS] set interfaces tunnel tun0 encapsulation ipip6
[VyOS] set interfaces tunnel tun0 source-address 2404:7a82:4d02:4100:85:d10d:200:4100
[VyOS] set interfaces tunnel tun0 remote 2404:9200:225:100::64
[VyOS] set interfaces tunnel tun0 address 133.209.13.2/32
[VyOS] set interfaces tunnel tun0 ip source-validation loose
[VyOS] set protocols static route 0.0.0.0/0 interface tun0
[VyOS] commit
```

#### 5. 全ポート範囲のNAPT設定

15ブロック分のルールを追加 (rule 200-214)

---

## 根本的な選択肢

| 選択肢 | 説明 | 実現可能性 |
|--------|------|-----------|
| **A: VyOSでMAP-E成功** | rp_filter緩和 + remote any | 要検証 |
| **B: VyOS停止してWXR単独** | 競合解消してWXRにMAP-E取得させる | 要検証 |

**選択肢Bの検証方法**:
1. VyOSのDHCPv6を一時停止
2. WXRを再起動
3. WXRがMAP-E (IPv6オプション) を取得できるか確認

これで競合が原因かどうかが判明する。

---

## 参考リンク

- [fakemanhk/openwrt-jp-ipoe](https://github.com/fakemanhk/openwrt-jp-ipoe) - OpenWrt MAP-E日本向けガイド
- [cernet/MAP](https://github.com/cernet/MAP) - MAP-E参照実装
- [Red Hat - Linux Virtual Interfaces: Tunnels](https://developers.redhat.com/blog/2019/05/17/an-introduction-to-linux-virtual-interfaces-tunnels)
- [Red Hat - Asymmetric Routing](https://access.redhat.com/solutions/53031) - rp_filter設定
- [m13253/userland-ipip](https://github.com/m13253/userland-ipip) - ユーザーランドトンネル実装
- [YAMAHA BIGLOBE IPv6接続](http://www.rtpro.yamaha.co.jp/RT/docs/biglobe/index.html)
- [MAP-Eパラメータ計算ツール](http://ipv4.web.fc2.com/map-e.html)
- [y2blog - MAP-Eの仕組み](https://y2tech.net/blog/inet/understanding-how-map-e-works-10955/)
- [VyOS Tunnel Documentation](https://docs.vyos.io/en/equuleus/configuration/interfaces/tunnel.html)

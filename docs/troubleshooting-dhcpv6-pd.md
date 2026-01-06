# トラブルシューティング: DHCPv6-PD取得問題

## 調査日時

2026-01-04

## 環境

- VyOS: 2026.01.03-0020-rolling (current)
- ハードウェア: HP ProDesk 600 G4 SFF
- WAN NIC: Intel X540-T2 (eth1, 10GbE)
- ISP: BIGLOBE光 10Gbps (IPv6 IPoE + MAP-E)

## 症状

1. DHCPv6 Solicitを送信しているが、サーバーからの応答がない
2. SLAACでグローバルIPv6アドレスが取得できない
3. 上流ルーターへのping6が100% loss

## 調査結果

### RA受信: OK

```
$ sudo rdisc6 eth1
Soliciting ff02::2 (ff02::2) on eth1...

Hop limit                 :           64 (      0x40)
Stateful address conf.    :          Yes
Stateful other conf.      :          Yes
Router preference         :       medium
Router lifetime           :         1800 (0x00000708) seconds
MTU                      :         1500 bytes (valid)
from fe80::a611:bbff:fe7d:ee11
```

- **Mフラグ (Stateful address) = Yes** → DHCPv6でアドレス取得可能
- **Oフラグ (Stateful other) = Yes** → DHCPv6で追加情報取得可能
- 送信元MACアドレス: A4:11:BB:7D:EE:11 (BIGLOBE側HGW/ONU)

### DHCPv6 Solicit: 送信中だが応答なし

```
$ show log | grep dhcp6c | tail -10
dhcp6c[3360]: client6_send: send solicit to ff02::1:2%eth1
dhcp6c[3360]: dhcp6_reset_timer: reset a timer on eth1, state=SOLICIT, timeo=16, retrans=125112
```

- DHCPv6 Solicitを継続的に送信
- サーバーからのAdvertise応答がない
- retransタイマーが増加し続けている

### ping6 上流ルーター: 100% loss

```
$ ping6 -c 3 fe80::a611:bbff:fe7d:ee11%eth1
PING fe80::a611:bbff:fe7d:ee11%eth1 56 data bytes
--- fe80::a611:bbff:fe7d:ee11%eth1 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2039ms
```

### tcpdump: 送信パケット未検出

```
$ sudo tcpdump -i eth1 -n icmp6 -c 10
00:24:50.940875 IP6 fe80::a611:bbff:fe7d:ee11 > ff02::1: ICMP6, router advertisement, length 32
```

- RAは受信できている
- ping6送信時のICMPv6 Echo Requestがキャプチャされない
- **VyOSからの送信パケットがeth1に出ていない可能性**

### eth1 IPv6状態

```
$ ip -6 addr show dev eth1
4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP
    inet6 fe80::c662:37ff:fe08:e53/64 scope link
       valid_lft forever preferred_lft forever
```

- リンクローカルアドレス (fe80::) のみ
- グローバルアドレスなし (SLAACが動作していない)

## 考えられる原因

### 1. 送信パケットがeth1に出ていない

- tcpdumpでping6のパケットが見えない
- ルーティングまたはインターフェース設定の問題の可能性

### 2. 上流側でフィルタリング

- RAは許可されているが、他のICMPv6がフィルタされている可能性
- ただし、DHCPv6も応答がないため、これだけが原因とは考えにくい

### 3. L2レベルの片方向通信

- 受信は正常だが送信に問題がある
- NIC/ドライバの問題の可能性

### 4. BIGLOBE側の制限

- DHCPv6-PDを提供しない設定になっている
- 特定のDUIDでのみPDを払い出す

## 次の調査ステップ

1. **送信経路の確認**
   ```
   ip -6 route show
   ip -6 neigh show dev eth1
   ```

2. **別のping先でテスト**
   ```
   ping6 -c 3 ff02::1%eth1
   ```

3. **tcpdumpで全パケット確認**
   ```
   sudo tcpdump -i eth1 -n ip6 -c 20
   ```

4. **NIC/ドライバの確認**
   ```
   ethtool eth1
   dmesg | grep -i x540
   ```

5. **IPv6 forwarding設定確認**
   ```
   sysctl net.ipv6.conf.eth1.forwarding
   sysctl net.ipv6.conf.eth1.accept_ra
   ```

## 関連設定 (現在)

```
set interfaces ethernet eth1 description 'WAN'
set interfaces ethernet eth1 ipv6 address autoconf
set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id '1'
set interfaces ethernet eth1 dhcpv6-options pd 0 length '56'
```

## 追加調査 (2026-01-04 17:45)

### WXRスクリーンショット分析

WXR9300BE6Pが正常動作していた時のスクショを分析:

- **IPv6アドレス**: グローバルIPv6を取得していた
- **IPv6プレフィックス**: /64 のみ表示
- **設定**: 「IPv6アドレスを自動取得」が選択

**重要な発見**: WXRは/56のDHCPv6-PDではなく、/64のみで動作していた可能性

### RAにPrefix Informationがない

```
$ sudo rdisc6 eth1
Hop limit                 :           64 (      0x40)
Stateful address conf.    :          Yes
Stateful other conf.      :          Yes
Router lifetime           :         1800 (0x00000708) seconds
MTU                      :         1500 bytes (valid)
from fe80::a611:bbff:fe7d:ee11
```

**Prefix Information が含まれていない**

通常のSLAAC環境では以下のようなPrefix情報がある:
```
Prefix                    : 2409:10:xxxx::/64
```

しかし、このRAには:
- Mフラグ = Yes (DHCPv6でアドレス取得せよ)
- Oフラグ = Yes (DHCPv6で追加情報取得せよ)
- **Prefixなし** → SLAACは使えない

**結論**: BIGLOBE NGNは「SLAACは使うな、DHCPv6でアドレスを取得せよ」と言っている

### DHCPv6 Solicit送信確認

```
$ sudo tcpdump -i eth1 -n -vvv -s0 port 547 or port 546 -c 3
17:42:02.612742 IP6 fe80::c662:37ff:fe08:e53.546 > ff02::1:2.547:
  dhcp6 solicit (xid=fa5ccd
    (client-ID type 4)
    (elapsed-time 65535)
    (IA_PD IAID:0 T1:0 T2:0 (IA_PD-prefix ::/56 pltime:4294967295 vltime:4294967295)))
```

- DHCPv6 Solicitは送信できている
- **IA_PD (Prefix Delegation)** を要求している
- サーバーからの応答なし

### 仮説: DHCPv6-PDではなくDHCPv6-NAが必要

現在の設定は**IA_PD (Prefix Delegation)** を要求しているが、
BIGLOBE側は**IA_NA (Non-temporary Address)** のみ提供している可能性がある。

## Web調査結果 (2026-01-04 18:00)

### フレッツ光クロスのIPv6仕様

参考:
- [IP実践道場 - ひかり電話契約の有無による配布方式の違い](https://note.com/noblehero0521/n/n6178786f2d12)
- [NTT西日本 フレッツ光クロス留意事項](https://flets-w.com/service/cross/ryuuijikou/)

**フレッツ光クロス(10G)の場合:**
- **ひかり電話契約の有無にかかわらず、DHCPv6-PD方式**
- **/56のプレフィックスが割り当てられる**
- RAにはPrefixが含まれない（Mフラグ=YesでDHCPv6を使えと指示）

**フレッツ光ネクスト(1G)の場合:**
- ひかり電話あり → DHCPv6-PD方式、/56
- ひかり電話なし → RA方式、/64のみ

### 結論

現在の設定方針 (DHCPv6-PDで/56要求) は**正しい**。

問題は「なぜDHCPv6 Solicitに応答がないか」である。

### 考えられる原因 (絞り込み)

1. ~~DHCPv6-PDではなくDHCPv6-NAが必要~~ → 光クロスはPD方式なので否定
2. **L2レベルで送信パケットが届いていない**
3. **BIGLOBE側で何らかの認証/制限がある**
4. **DHCPv6クライアントのオプションが不正**

## 次の試行

### 試行1: DHCPv6 Solicitパケットの詳細確認

tcpdumpでSolicitパケットの中身を詳細確認し、他のルーターの例と比較する。

### 試行2: 上流ルーターへのL2到達性確認

```
sudo arping -I eth1 fe80::a611:bbff:fe7d:ee11
```

ICMPv6ではなくARPで到達性を確認。

### 試行3: NDP Neighbor Solicitationの確認

```
ip -6 neigh show dev eth1
```

### 試行4: VyOS DHCPv6クライアントのデバッグログ確認

```
show log | grep dhcp6c | tail -30
```

## 追加調査 (2026-01-04 18:15)

### 物理構成の確認

- eth1 → ONU直結 (L2スイッチなし)
- eth2 → Mac直結
- WXRは電源OFF、完全切り離し
- ONUのポートは1つのみ

### L2到達性の調査

#### Neighborテーブル: OK
```
$ ip -6 neigh show dev eth1
fe80::a611:bbff:fe7d:ee11 lladdr a4:11:bb:7d:ee:11 router STALE
```
- 上流ルーターのMACアドレスは解決できている

#### ping6送信: OK、応答なし
```
$ ping6 -c 3 fe80::a611:bbff:fe7d:ee11%eth1
3 packets transmitted, 0 received, 100% packet loss
```

#### tcpdumpでの送信確認: 送信OK
```
$ sudo tcpdump -i eth1 -n icmp6 -c 10
18:09:38.271059 IP6 fe80::c662:37ff:fe08:e53 > fe80::a611:bbff:fe7d:ee11: ICMP6, echo request, id 12000, seq 1, length 64
18:09:39.303363 IP6 fe80::c662:37ff:fe08:e53 > fe80::a611:bbff:fe7d:ee11: ICMP6, echo request, id 12000, seq 2, length 64
18:09:40.327362 IP6 fe80::c662:37ff:fe08:e53 > fe80::a611:bbff:fe7d:ee11: ICMP6, echo request, id 12000, seq 3, length 64
```
- Echo Requestはeth1から送信されている

#### 上流からの受信パケット確認
```
$ sudo tcpdump -i eth1 -n -e ether src a4:11:bb:7d:ee:11
18:11:46.245309 a4:11:bb:7d:ee:11 > 33:33:00:00:00:01, ethertype IPv6 (0x86dd), length 86:
  fe80::a611:bbff:fe7d:ee11 > ff02::1: ICMP6, router advertisement, length 32
```

**重要な発見:**
- 上流からは**RAマルチキャスト(ff02::1宛)のみ**受信
- **ユニキャスト応答(Echo Reply, DHCPv6 Advertise)は一切受信していない**

### NIC状態確認

```
$ ethtool eth1 | head -20
Speed: 10000Mb/s
Duplex: Full
Auto-negotiation: on
```
- 10Gbpsでリンクアップ、正常

### ファイアウォール確認

```
$ show firewall
ipv6 Firewall "forward filter"
Rule 10: accept established, related from eth1
Rule 20-24: accept ICMPv6 (echo-request, nd-*, ra)
default: drop
```

**注意:** これは**forward filter**であり、**input filter**ではない。
VyOS自身宛のパケット(input)にはこのルールは適用されない。

### 現時点での状況整理

| 項目 | 状態 |
|------|------|
| L2リンク | OK (10Gbps) |
| RAマルチキャスト受信 | OK |
| Neighbor解決 | OK |
| Echo Request送信 | OK |
| Echo Reply受信 | NG |
| DHCPv6 Solicit送信 | OK |
| DHCPv6 Advertise受信 | NG |

**結論:** VyOSからの送信は正常だが、上流からのユニキャスト応答が届かない。

### 考えられる原因

1. **ONU/NGN側で、未知のMACアドレスからのパケットを無視している**
   - WXRのMACアドレスのみ許可されている可能性
   - ただし、MACアドレス認証は否定済み（別ルーターに変えたら使えなくなる議論）

2. **上流ルーターがVyOSのMACアドレスへの応答経路を持っていない**
   - 片方向通信状態

3. **何らかのL2/L3フィルタリング**

## Web調査結果 (2026-01-04 18:20) - DUID設定の重要性

### 参考記事

- [フレッツ光 クロス + VyOSでインターネットに接続しようとして失敗した話](https://zenn.dev/sdb_blog/articles/353e1855111737)
- [光クロスでDHCPv6-PDを受ける VyOS編](https://kazukichi.jp/archives/1200)

### 重要な発見: DUID-LL形式の設定が必須

**フレッツ網(NGN)ではDHCPv6のDUIDをDUID-LL形式に設定する必要がある。**

NTT東の「IP通信網サービスのインタフェース第三分冊」より:
> 端末側のDUID生成方式はRFC3315に規定されるDUID-LL方式に準拠する必要があります。

DUID-LL形式: `00:03:00:01:[MACアドレス]`

- `00:03` = DUID-LL type
- `00:01` = Ethernet hardware type
- `[MACアドレス]` = NICのMACアドレス

### VyOSでのDUID設定方法

```
set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:c4:62:37:08:0e:53'
```

eth1のMACアドレス `c4:62:37:08:0e:53` を使用。

### 現在の設定に不足しているもの

現在の設定:
```
set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id '1'
set interfaces ethernet eth1 dhcpv6-options pd 0 length '56'
```

不足: **duid設定がない**

### VyOS固有の問題

参考記事によると、VyOSでは:
- WANインターフェースにIPv6アドレスが付与されない問題がある
- 同じ設定でOpenWrtでは動作するがVyOSでは失敗する例あり
- DHCPv6 PDの使用時に委譲したプレフィックスのルートがルーターに注入されないバグがある

ただし、DUID設定なしでは「Prefixなどの必要な情報も取得できない」とのこと。

## 次の試行

### 試行: DUID-LL設定を追加

```
configure
set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:c4:62:37:08:0e:53'
commit
```

その後、DHCPv6クライアントを再起動:
```
restart dhcpv6 client interface eth1
```

## 試行記録 (2026-01-04 18:30-)

### 試行1: DUID-LL設定をVyOS configで追加

```
set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:c4:62:37:08:0e:53'
commit
```

結果: 設定は反映されたが、dhcp6cは `/var/lib/dhcpv6/dhcp6c_duid` の古いDUIDを優先して使用

### 試行2: 古いDUIDファイルを削除して再実行

```
sudo rm /var/lib/dhcpv6/dhcp6c_duid
sudo dhcp6c -D -f -c /run/dhcp6c/dhcp6c.eth1.conf eth1
```

結果: 新しいDUID (`00:01:...` DUID-LLT形式) が自動生成されたが、応答なし

### 試行3: DUIDファイルを手動作成 (DUID-LL形式)

```
printf '\x00\x0a\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' | sudo tee /var/lib/dhcpv6/dhcp6c_duid
```

結果: `DUID file corrupted` エラー

### 試行4: DUIDファイル形式を調査・修正

```
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' | sudo tee /var/lib/dhcpv6/dhcp6c_duid
```

結果: DUIDは正しく読み込まれた (`00:03:00:01:c4:62:37:08:0e:53`) が、応答なし

### 試行5: xxdコマンドで古いDUID復元を試みる

```
echo '00:04:c7:e4:54:99:1c:dc:93:4c:ce:8f:ed:a9:1c:e4:a7:b1' | awk '{ gsub(":"," "); printf "0: 12 00 %s\n", $0 }' | xxd -r | sudo tee /var/lib/dhcpv6/dhcp6c_duid
```

結果: `Invalid command: [xxd]` - VyOSにxxdがインストールされていない

### 重要な発見

最初のdhcp6c実行時 (デフォルト設定ファイル使用時):
- 古いDUID (`00:04:...`) で Advertise を受信
- プレフィックス `2404:7a82:4d02:4100::/56` が返ってきた
- しかし `XID mismatch` で処理されなかった

XID mismatchの原因:
- デフォルト設定 (`/etc/wide-dhcpv6/dhcp6c.conf`) は `information-only` で IA-PD を要求していない
- サーバーは別のクライアント (以前のセッション?) への応答を返している可能性

### 試行6: 古いDUID (DUID-UUID) + send client-id削除

```
printf '\x12\x00\x00\x04\xc7\xe4\x54\x99\x1c\xdc\x93\x4c\xce\x8f\xed\xa9\x1c\xe4\xa7\xb1' | sudo tee /var/lib/dhcpv6/dhcp6c_duid
sudo dhcp6c -D -f -c /tmp/dhcp6c.eth1.conf eth1
```

結果: DUIDは正しく読み込まれた (`client ID (len 18)`)、しかし応答なし

## Deep Research結果 (2026-01-04 18:55)

### 検索クエリと結果

#### 検索1: "DHCPv6 solicit no response IA-PD prefix delegation フレッツ NGN VyOS wide-dhcpv6"

参考記事:
- [VyOS Forums: Yet another IPv6 prefix delegation problem](https://forum.vyos.io/t/yet-another-ipv6-prefix-delegation-problem/11304)
- [VyOS Forums: DHCPv6-PD issues](https://forum.vyos.io/t/dhcpv6-pd-issues/7292)
- [Debian Manpages: dhcp6c.conf(5)](https://manpages.debian.org/testing/wide-dhcpv6-client/dhcp6c.conf.5.en.html)

主な知見:
- ISPによっては/60プレフィックスをカスタムIA_PDプレフィックスで渡すが、デフォルトだと/64になることがある
- VyOSのDHCPv6 PDには委譲されたプレフィックスのルートが注入されないバグがある
- 一部のCPEはIA_NAとIA_PDを別々のSolicitで送るが、単一メッセージで送る必要がある場合がある

#### 検索2: "フレッツ光クロス DHCPv6-PD 取得できない Solicit Advertise 応答なし DUID"

参考記事:
- [光クロスでCisco機材用いたらREQUESTのままPDが降ってこなかった件](https://azutake.hatenablog.jp/entry/2023/12/07/113048)
- [光クロスでDHCPv6-PDを受ける VyOS編](https://kazukichi.jp/archives/1200)
- [NTT東日本 技術参考資料 IP通信網サービスのインタフェース 第三分冊](https://www.ntt-east.co.jp/info-st/katsuyou/2019/temp20-1.pdf)
- [FortiGate IPoE設定ガイド フレッツ光クロス対応版](https://www.fortinet.com/content/dam/fortinet/assets/deployment-guides/ja_jp/fg-ocn-ipoe-fixip-hikari-cross.pdf)

### 重要な発見: NGNはDUID-LL形式のみ受け付ける

NTT東の技術参考資料より:
> IP通信網のDUID生成方式はRFC3315に規定されるDUID-LL方式であり、MACアドレスからDUIDを生成します。
> 端末側のDUID生成方式はRFC3315に規定されるDUID-LL方式に準拠する必要があります。
> 端末機器もIP通信網と同様にMACアドレスからDUIDを生成する必要があります。

別の記事より:
> NGN の DHCPv6-PD は CID に DUID-LL が必須です。DUID-LLT, DUID-EN じゃダメなので注意。
> DUID-LL 以外だと黙って solicit パケットが無視されます。

DUID形式:
- `00:01:...` = DUID-LLT (Link Layer + Time) → NG
- `00:02:...` = DUID-EN (Enterprise Number) → NG
- `00:03:...` = DUID-LL (Link Layer) → OK
- `00:04:...` = DUID-UUID → NG

### Cisco機器での問題と解決策

[azutake.hatenablog.jp](https://azutake.hatenablog.jp/entry/2023/12/07/113048)より:
- Zero Touch Provisioningが原因でREQUESTのままPDが降ってこない
- 解決策: プレフィックスヒントを明示的に指定
  ```
  ipv6 dhcp client pd hint 2400:4151:xxxx:xxxx::/56
  ```
- IOS-XE 17.10.1a以降ではSOLICIT自体が無視される問題あり

### VyOSでの推奨設定

[kazukichi.jp](https://kazukichi.jp/archives/1200)より:
```
set interfaces ethernet ethX ipv6 address autoconf
set interfaces ethernet ethX dhcpv6-options duid 00:03:00:01:AA:BB:CC:DD:EE:FF
set interfaces ethernet ethX dhcpv6-options pd 0 interface ethY address 1
set interfaces ethernet ethX dhcpv6-options pd 0 interface ethY sla-id 1
set interfaces ethernet ethX dhcpv6-options pd 0 length 56
```

注意: VyOSではWANインターフェースにIPv6アドレスが付与されない問題がある

### 矛盾点の分析

最初の実行時:
- 使用DUID: `00:04:...` (DUID-UUID) → NGNに無視されるはず
- しかしAdvertiseが返ってきた
- XID mismatch で処理されなかった

考えられる説明:
1. 返ってきたAdvertiseは**別のクライアント（WXR？）への応答**だった可能性
2. WXRの電源は切っているが、NGN側にキャッシュが残っていて応答が返ってきた
3. XID mismatchはVyOSが送ったSolicitとは別のトランザクションへの応答だった

### 試行すべきこと

1. **DUID-LL形式で再試行** (既に試したが応答なし)
2. **WXRのMACアドレスでDUID-LLを作成** → NGNがWXRのDUIDを期待している可能性
3. **オンボードNIC (eth0) のMACアドレスでDUID-LLを作成** → 別のNICで試す

## Claude相談 (2026-01-04 19:00)

### 相談内容

```
【相談: VyOS DHCPv6-PD フレッツ光クロスでAdvertiseが返ってこない】

## 1️⃣ 何が起きているか(事実)

環境:
- ISP: BIGLOBE光 10Gbps (フレッツ光クロス)
- ルーター: VyOS 2026.01.03-rolling (HP ProDesk 600 G4 SFF)
- WAN NIC: Intel X540-T2 (eth1) - ONU直結
- 以前使用: BUFFALO WXR9300BE6P (現在電源OFF)

確認できていること:
- RAは受信できている (Mフラグ=Yes, Oフラグ=Yes, Prefixなし)
- DHCPv6 Solicitは送信できている (tcpdumpで確認)
- Neighborテーブルに上流ルーター登録済み (fe80::a611:bbff:fe7d:ee11)
- ping6 上流ルーター → 100% loss (Echo Requestは送信されているがReplyなし)

## 2️⃣ 試したことと結果

1. VyOS標準のDHCPv6-PD設定 → 応答なし
2. DUID-LL形式 (00:03:00:01:c4:62:37:08:0e:53) を設定 → 応答なし
3. 古いDUID (00:04:... DUID-UUID形式) で試行 → 応答なし
4. dhcp6cを手動実行 (-D -f オプション) → 応答なし

## 3️⃣ 重要な発見

最初のdhcp6c実行時 (デフォルト設定ファイル使用時):
- 使用DUID: 00:04:c7:e4:54:99:1c:dc:93:4c:ce:8f:ed:a9:1c:e4:a7:b1 (DUID-UUID)
- Advertiseを受信した！
  - プレフィックス: 2404:7a82:4d02:4100::/56
  - サーバーID: 00:03:00:01:00:50:56:85:42:68
- しかし「XID mismatch」で処理されなかった

## 4️⃣ 矛盾点

- NGNはDUID-LL形式のみ受け付けるはず
- しかしDUID-UUID (00:04:...) でAdvertiseが返ってきた
- DUID-LL形式 (00:03:...) では応答がない

## 5️⃣ 仮説

1. 返ってきたAdvertiseはWXR（以前のルーター）への応答だった可能性
   - WXRの電源は切っているが、NGN側にキャッシュが残っている
   - XID mismatchは別のトランザクションへの応答だったため

2. NGNがWXRのDUIDを期待している
   - WXRのMACアドレスでDUID-LLを作成すれば動く可能性

## 6️⃣ 質問

1. 最初にAdvertiseが返ってきたのは、本当にVyOSのSolicitへの応答だったのか？
   それとも別のクライアント（WXR）への応答がたまたま見えただけか？

2. NGNはDUID-LL以外を無視するはずなのに、DUID-UUIDでAdvertiseが返ってきたのはなぜか？

3. 次に試すべきことは何か？
   - WXRのMACアドレスでDUID-LLを作成？
   - ONUの再起動？
   - 別のアプローチ？
```

### Claudeの回答 (2026-01-04 19:10)

#### 分析結果

**核心的な矛盾点の解釈:**
- DUID-UUID (00:04:...)でAdvertiseが返ってきた → 仮説: WXRへの応答を傍受しただけ
- XID mismatch → 別のクライアント(WXR)への応答だったため
- サーバーID `00:03:00:01:00:50:56:85:42:68` のMAC `00:50:56` はVMware OUI → NGN側の仮想サーバー

**仮説1: WXRへの応答がたまたま見えた (可能性: 高)**
- WXRは電源OFFだが、NGN側のDHCPv6サーバーにはリース情報が残っている
- DHCPv6はマルチキャスト(ff02::1:2)で送受信 → 同一セグメントの全ノードが受信可能
- VyOSのSolicitは実際には無視されていた

#### 推奨アクション

**案1 + 案3の組み合わせ:**
1. ONU再起動でNGN側のセッション/キャッシュをクリア (5分以上OFF)
2. 正しいDUID-LL形式 (`00:03:00:01:c4:62:37:08:0e:53`) で再試行

#### WXRの情報 (スクショより)

- **MACアドレス:** F0:F8:4A:67:58:00
- **CEアドレス:** 2404:7a82:4d02:4100:85:d10d:200:4100
- **グローバルアドレス:** 2404:7a82:4d02:4100:f2f8:4aff:fe67:5800/56
- **プレフィックス:** 2404:7a82:4d02:4100::/56 (最初のAdvertiseと一致！)

## 次のアクション

### 選択肢A: ONU再起動 (推奨)
1. ONU電源OFF → 5分以上待機 → 電源ON
2. eth1のMACアドレスでDUID-LL設定確認
3. dhcp6c再試行

### 選択肢B: WXRのMACでDUID-LL試行 (ONU再起動前に試す)
```bash
printf '\x0a\x00\x00\x03\x00\x01\xf0\xf8\x4a\x67\x58\x00' | sudo tee /var/lib/dhcpv6/dhcp6c_duid > /dev/null
sudo dhcp6c -D -f -c /tmp/dhcp6c.eth1.conf eth1
```

## Claude追加回答 (2026-01-04 19:15)

### 確認事項への回答

1. WXRのWAN側MACアドレス: `F0:F8:4A:67:58:00` (確認済み)
2. ONU再起動のタイミング: 制約なし、いつでも可能
3. WXRで取得していたプレフィックス: `2404:7a82:4d02:4100::/56` (確認済み)

### 修正された解決案

**案D (MACアドレス偽装 + WXRのDUID-LL) が最終推奨**

理由:
- NGNはDUID-LLの中のMACアドレスと実際のL2フレームのSource MACの両方を見ている可能性
- 両方をWXRに合わせれば「WXRが復帰した」ように見える
- ONU再起動なしでまず試せる

### 実装手順

```bash
# 1. eth1のMACアドレスをWXRに偽装
ip link set eth1 down
ip link set eth1 address f0:f8:4a:67:58:00
ip link set eth1 up

# 2. WXRのDUID-LLでdhcp6c_duidファイル作成
printf '\x0a\x00\x00\x03\x00\x01\xf0\xf8\x4a\x67\x58\x00' | sudo tee /var/lib/dhcpv6/dhcp6c_duid > /dev/null

# 3. DHCPv6-PD試行
sudo dhcp6c -D -f -c /tmp/dhcp6c.eth1.conf eth1
```

### 注意事項

以前の議論「MACアドレス偽装は別のルーターに変えたら使えなくなる」を踏まえ、
これは**一時的な検証**として実施。動作確認後、正しい方法に移行する予定。

## 試行7: 案D (MAC偽装 + WXR DUID-LL) (2026-01-04 19:18)

### 実施手順

```bash
# MACアドレス偽装
sudo ip link set eth1 down
sudo ip link set eth1 address f0:f8:4a:67:58:00
sudo ip link set eth1 up

# リンクローカルアドレス手動設定 (MAC変更後に消えたため)
sudo ip -6 addr add fe80::f2f8:4aff:fe67:5800/64 dev eth1 scope link

# WXRのDUID-LL設定
printf '\x0a\x00\x00\x03\x00\x01\xf0\xf8\x4a\x67\x58\x00' | sudo tee /var/lib/dhcpv6/dhcp6c_duid > /dev/null

# DHCPv6-PD試行
sudo dhcp6c -D -f -c /tmp/dhcp6c.eth1.conf eth1
```

### 結果

- MACアドレス変更: 成功 (`f0:f8:4a:67:58:00`)
- DUID-LL: 正しく読み込まれた (`00:03:00:01:f0:f8:4a:67:58:00`)
- Solicit送信: 成功 (`send solicit to ff02::1:2%eth1`)
- **Advertise受信: なし** - 応答がない

### 考察

WXRのMAC + DUID-LLでも応答がないということは:
1. NGN側のWXRのセッション/リースがタイムアウトしている
2. または、DHCPv6サーバーがリセットされている

**結論: ONU再起動が必要**

## 解決 (2026-01-06)

### 解決手順

ONU再起動後、以下の手順で解決:

#### 1. 問題の切り分け (困難は分割せよ)

| # | 確認項目 | 結果 |
|---|----------|------|
| 1 | L1: 物理リンク | OK (`show interfaces` で u/u) |
| 2 | L2: MACレベル通信 | OK (RA受信できている) |
| 3 | L3: リンクローカル通信 | OK (ndisc6でNA応答あり) |
| 4 | DHCPv6: DUID形式 | **NG** (DUID-UUID形式だった) |

**補足**: ping6が100% lossだったのはNGN側でICMPv6 Echo Replyを無効化しているため (NA応答は返ってくる)

#### 2. DUIDファイルの修正

```bash
# DHCPv6クライアント停止
sudo systemctl stop dhcp6c@eth1 2>/dev/null || true

# DUID-LL形式でファイル作成
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' | sudo tee /var/lib/dhcpv6/dhcp6c_duid > /dev/null

# 確認
od -A x -t x1z /var/lib/dhcpv6/dhcp6c_duid
# 出力: 0a 00 00 03 00 01 c4 62 37 08 0e 53
```

**ファイル形式の説明**:
- `0a 00` = 長さ (10バイト、リトルエンディアン)
- `00 03` = DUID-LL type
- `00 01` = Ethernet hardware type
- `c4 62 37 08 0e 53` = eth1のMACアドレス

#### 3. DHCPv6クライアント再起動

```bash
sudo systemctl restart dhcp6c@eth1
```

#### 4. 結果確認

```
$ sudo tcpdump -i eth1 -n port 546 or port 547 -c 4
dhcp6 solicit
dhcp6 advertise
dhcp6 request
dhcp6 reply
```

```
$ show interfaces
eth2: 2404:7a82:4d02:4101:c662:37ff:fe08:e52/64
```

```
$ ping6 -c 3 2001:4860:4860::8888
3 packets transmitted, 3 received, 0% packet loss
```

### 根本原因

**DUIDがDUID-LL形式でなかった**

| 形式 | プレフィックス | NGN対応 |
|------|----------------|---------|
| DUID-LLT | `00:01:...` | NG |
| DUID-EN | `00:02:...` | NG |
| DUID-LL | `00:03:...` | **OK** |
| DUID-UUID | `00:04:...` | NG |

NTT NGN (フレッツ網) はDUID-LL形式のみを受け付け、それ以外のDHCPv6 Solicitは**黙って無視する**。

VyOSのwide-dhcpv6-clientはデフォルトでDUID-UUID (`00:04:...`) を生成するため、手動でDUID-LLファイルを作成する必要があった。

### 永続化設定

VyOS設定に以下を追加して永続化:

```
configure
set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:c4:62:37:08:0e:53'
commit
save
```

### 教訓

1. **NGNのDHCPv6-PDはDUID-LL必須** - 他の形式は黙って無視される
2. **ping6が通らなくてもL3は正常な場合がある** - NDPのNA応答で確認すべき
3. **問題は分割して切り分ける** - L1→L2→L3→アプリケーション層の順に確認

## ステータス

**解決済み** (2026-01-06)

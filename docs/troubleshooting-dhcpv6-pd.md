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

## ステータス

**未解決** - 追加調査が必要

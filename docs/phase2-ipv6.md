# Phase 2: IPv6基盤構築

## タスク2-1: RA受信・DHCPv6-PD取得

**目的**: 自作ルーターがONUから直接IPv6アドレス/プレフィックスを取得

**VyOSコマンド**:
```
configure

set interfaces ethernet eth1 description 'WAN'
set interfaces ethernet eth1 ipv6 address autoconf
set interfaces ethernet eth1 dhcpv6-options pd 0 length 56
set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id 1

commit
save
```

**注意点**:
- WXRがまだ接続されている場合、先にWXRのRA配布を停止しておく
- インターフェース名: eth1=WAN (10GbE)、eth2=LAN (10GbE)、eth0=WXR接続 (1GbE)

**完了条件**: グローバルIPv6アドレス取得、`show interfaces`で確認

---

## タスク2-2: LAN側RA配布設定

**目的**: LANクライアントにIPv6アドレスを自動配布

**VyOSコマンド**:
```
configure

set service router-advert interface eth2 prefix ::/64
set service router-advert interface eth2 name-server <IPv6 DNS>

commit
save
```

**注意点**:
- **RAは自作ルーターのみが配布**
- **WXR側LANには絶対にRAを出させない**

**完了条件**: クライアントがIPv6取得、外部IPv6サイトにアクセス可能

---

## タスク2-3: IPv6ファイアウォール設定 (forward filter)

**目的**: WAN側からの不正アクセス遮断

**VyOSコマンド** (VyOS 2024.x以降の新構文):
```
configure

# forward filter: WAN(eth1)からLANへの転送トラフィック制御
set firewall ipv6 forward filter default-action drop

# 確立済み/関連セッション許可
set firewall ipv6 forward filter rule 10 action accept
set firewall ipv6 forward filter rule 10 state established
set firewall ipv6 forward filter rule 10 state related
set firewall ipv6 forward filter rule 10 inbound-interface name eth1

# ICMPv6 (必要なタイプのみ許可)
set firewall ipv6 forward filter rule 20 action accept
set firewall ipv6 forward filter rule 20 protocol icmpv6
set firewall ipv6 forward filter rule 20 icmpv6 type-name echo-request
set firewall ipv6 forward filter rule 20 inbound-interface name eth1

set firewall ipv6 forward filter rule 21 action accept
set firewall ipv6 forward filter rule 21 protocol icmpv6
set firewall ipv6 forward filter rule 21 icmpv6 type-name nd-neighbor-solicit
set firewall ipv6 forward filter rule 21 inbound-interface name eth1

set firewall ipv6 forward filter rule 22 action accept
set firewall ipv6 forward filter rule 22 protocol icmpv6
set firewall ipv6 forward filter rule 22 icmpv6 type-name nd-neighbor-advert
set firewall ipv6 forward filter rule 22 inbound-interface name eth1

set firewall ipv6 forward filter rule 23 action accept
set firewall ipv6 forward filter rule 23 protocol icmpv6
set firewall ipv6 forward filter rule 23 icmpv6 type-name nd-router-solicit
set firewall ipv6 forward filter rule 23 inbound-interface name eth1

set firewall ipv6 forward filter rule 24 action accept
set firewall ipv6 forward filter rule 24 protocol icmpv6
set firewall ipv6 forward filter rule 24 icmpv6 type-name nd-router-advert
set firewall ipv6 forward filter rule 24 inbound-interface name eth1

commit
save
```

**注意点**:
- VyOS 2024.x以降では `firewall ipv6 name` + インターフェース適用ではなく、`forward filter` + `inbound-interface` で指定
- ICMPv6タイプは `type-name` で指定 (例: `nd-neighbor-solicit`)
- 必要なICMPv6タイプのみ許可 (全許可は危険)
- 許可タイプ: echo-request, NS, NA, RS, RA

**完了条件**:
- [ ] 外部からpingに応答する (echo-request許可のため)
- [ ] 内部からIPv6サイトに通信可能
- [ ] 外部からSSH等の不正アクセスは拒否される

**補足**: echo-request(ping)を許可しているのは、ネットワーク診断のため。セキュリティを優先する場合はrule 20を削除してpingも拒否可能。

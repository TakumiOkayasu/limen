# Phase 2: IPv6基盤構築

## タスク2-1: RA受信・DHCPv6-PD取得

**目的**: 自作ルーターがONUから直接IPv6アドレス/プレフィックスを取得

**VyOSコマンド**:
```
configure

set interfaces ethernet eth0 description 'WAN'
set interfaces ethernet eth0 ipv6 address autoconf
set interfaces ethernet eth0 dhcpv6-options pd 0 length 56
set interfaces ethernet eth0 dhcpv6-options pd 0 interface eth1 sla-id 1

commit
save
```

**注意点**:
- WXRがまだ接続されている場合、先にWXRのRA配布を停止しておく
- eth0=WAN、eth1=LANの想定(実際のインターフェース名は要確認)

**完了条件**: グローバルIPv6アドレス取得、`show interfaces`で確認

---

## タスク2-2: LAN側RA配布設定

**目的**: LANクライアントにIPv6アドレスを自動配布

**VyOSコマンド**:
```
configure

set service router-advert interface eth1 prefix ::/64
set service router-advert interface eth1 name-server <IPv6 DNS>

commit
save
```

**注意点**:
- **RAは自作ルーターのみが配布**
- **WXR側LANには絶対にRAを出させない**

**完了条件**: クライアントがIPv6取得、外部IPv6サイトにアクセス可能

---

## タスク2-3: IPv6ファイアウォール設定（WAN6_IN作成）

**目的**: WAN側からの不正アクセス遮断

**VyOSコマンド**:
```
configure

set firewall ipv6 name WAN6_IN default-action drop

# 確立済み/関連セッション許可
set firewall ipv6 name WAN6_IN rule 10 action accept
set firewall ipv6 name WAN6_IN rule 10 state established enable
set firewall ipv6 name WAN6_IN rule 10 state related enable

# ICMPv6 (必要なタイプのみ許可)
set firewall ipv6 name WAN6_IN rule 20 action accept
set firewall ipv6 name WAN6_IN rule 20 protocol icmpv6
set firewall ipv6 name WAN6_IN rule 20 icmpv6 type echo-request

set firewall ipv6 name WAN6_IN rule 21 action accept
set firewall ipv6 name WAN6_IN rule 21 protocol icmpv6
set firewall ipv6 name WAN6_IN rule 21 icmpv6 type neighbor-solicitation

set firewall ipv6 name WAN6_IN rule 22 action accept
set firewall ipv6 name WAN6_IN rule 22 protocol icmpv6
set firewall ipv6 name WAN6_IN rule 22 icmpv6 type neighbor-advertisement

set firewall ipv6 name WAN6_IN rule 23 action accept
set firewall ipv6 name WAN6_IN rule 23 protocol icmpv6
set firewall ipv6 name WAN6_IN rule 23 icmpv6 type router-solicitation

set firewall ipv6 name WAN6_IN rule 24 action accept
set firewall ipv6 name WAN6_IN rule 24 protocol icmpv6
set firewall ipv6 name WAN6_IN rule 24 icmpv6 type router-advertisement

# インターフェースに適用
set interfaces ethernet eth0 firewall in ipv6-name WAN6_IN

commit
save
```

**注意点**:
- 必要なICMPv6タイプのみ許可（全許可は危険）
- 許可タイプ: echo-request, NS, NA, RS, RA

**完了条件**: 外部からping不可、内部から通信可

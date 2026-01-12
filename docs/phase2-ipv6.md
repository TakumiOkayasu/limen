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

**目的**: LANクライアントにIPv6アドレスを自動配布 (SLAAC)

**VyOSコマンド**:
```
configure

# eth2 (LAN) でRA配布を有効化
# プレフィックスはDHCPv6-PDで取得した /56 から sla-id 1 で割り当てられた /64
set service router-advert interface eth2 prefix 2404:7a82:4d02:4101::/64

# DNSサーバー (Cloudflare + Google)
set service router-advert interface eth2 name-server 2606:4700:4700::1111
set service router-advert interface eth2 name-server 2606:4700:4700::1001
set service router-advert interface eth2 name-server 2001:4860:4860::8888

commit
save
```

**確認コマンド**:
```bash
# VyOSでRA設定を確認
show configuration commands | grep router-advert

# クライアント側でIPv6アドレス取得を確認
# [Mac] ifconfig en0 | grep inet6
# → 2404:7a82:4d02:4101:... のアドレスが表示されればOK

# クライアント側でIPv6疎通確認
# [Mac] ping6 -c 3 2606:4700:4700::1111
# [Mac] curl -6 https://ifconfig.me
```

**注意点**:
- **RAは自作ルーターのみが配布** - WXRのRA配布は必ずOFFにする
- **WXR側LANには絶対にRAを出させない** - 干渉するとクライアントがWXRをデフォルトGWと認識してしまう
- プレフィックスは固定値ではなくDHCPv6-PDで取得したものを使う (BIGLOBEでは `2404:7a82:4d02:41XX::/64` の形式)

**トラブルシューティング**:
- クライアントがIPv6を取得できない場合:
  1. `show configuration commands | grep router-advert` で設定確認
  2. クライアント側で `ndp -rn` (Mac) でRAの送信元を確認
  3. WXRからRAが来ている場合はWXR側でRA配布をOFFに

**完了条件**:
- [x] クライアントがグローバルIPv6アドレスを取得 (`2404:7a82:4d02:4101:...`)
- [x] `ping6 2606:4700:4700::1111` が成功
- [x] `curl -6 https://ifconfig.me` でVyOS配下のIPv6アドレスが表示される

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

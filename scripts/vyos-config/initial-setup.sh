#!/bin/vbash
# VyOS Initial Setup Script
# Usage: source /config/scripts/initial-setup.sh
#
# このスクリプトはVyOSインストール後に実行する初期設定スクリプトです。
# SSHでアクセスできるようになるまでの最小限の設定を行います。
#
# 実行方法:
# 1. VyOSコンソールにログイン
# 2. configure
# 3. このスクリプトの内容をコピー＆ペースト
# 4. commit && save

source /opt/vyatta/etc/functions/script-template

# ========================================
# Phase 0: 基本設定
# ========================================

# ホスト名
set system host-name 'vyos-router'

# タイムゾーン
set system time-zone 'Asia/Tokyo'

# NTPサーバー
set service ntp server ntp.nict.jp
set service ntp server ntp.jst.mfeed.ad.jp
set service ntp allow-client address '127.0.0.0/8'
set service ntp allow-client address '192.168.0.0/16'
set service ntp allow-client address '::1/128'
set service ntp allow-client address 'fe80::/10'

# DNSサーバー (IPv6)
set system name-server '2606:4700:4700::1111'
set system name-server '2606:4700:4700::1001'
set system name-server '2001:4860:4860::8888'

# ========================================
# Phase 1: SSH設定
# ========================================

# SSH公開鍵 (macbook)
set system login user vyos authentication public-keys macbook type 'ssh-ed25519'
set system login user vyos authentication public-keys macbook key 'AAAAC3NzaC1lZDI1NTE5AAAAIOpNdmh8gsi6GLWApqb30Sm80cDK7j7sXYJhYP0feII3'

# SSHサービス
set service ssh port '22'
set service ssh listen-address '192.168.1.1'
set service ssh disable-password-authentication

# ========================================
# Phase 2: インターフェース設定
# ========================================

# eth0: WXR接続 (IPv4 transit)
set interfaces ethernet eth0 description 'To WXR LAN (IPv4 transit)'
set interfaces ethernet eth0 address '192.168.100.2/24'

# eth1: WAN (10GbE)
set interfaces ethernet eth1 description 'WAN'
set interfaces ethernet eth1 ipv6 address autoconf
set interfaces ethernet eth1 dhcpv6-options pd 0 length 56
set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id 1

# eth2: LAN (10GbE)
set interfaces ethernet eth2 description 'LAN'
set interfaces ethernet eth2 address '192.168.1.1/24'

# ========================================
# Phase 2: RA配布設定
# ========================================

set service router-advert interface eth2 prefix '2404:7a82:4d02:4101::/64'
set service router-advert interface eth2 name-server '2606:4700:4700::1111'
set service router-advert interface eth2 name-server '2606:4700:4700::1001'
set service router-advert interface eth2 name-server '2001:4860:4860::8888'

# ========================================
# Phase 2: IPv6 ファイアウォール (forward filter)
# ========================================

set firewall ipv6 forward filter default-action drop
set firewall ipv6 forward filter default-log

# established/related許可
set firewall ipv6 forward filter rule 10 action accept
set firewall ipv6 forward filter rule 10 state established
set firewall ipv6 forward filter rule 10 state related
set firewall ipv6 forward filter rule 10 inbound-interface name eth1

# ICMPv6許可
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

# ========================================
# Phase 2: IPv6 ファイアウォール (input filter)
# ========================================

set firewall ipv6 input filter default-action drop
set firewall ipv6 input filter default-log

set firewall ipv6 input filter rule 10 action accept
set firewall ipv6 input filter rule 10 state established
set firewall ipv6 input filter rule 10 state related

set firewall ipv6 input filter rule 20 action accept
set firewall ipv6 input filter rule 20 protocol icmpv6

set firewall ipv6 input filter rule 30 action accept
set firewall ipv6 input filter rule 30 protocol udp
set firewall ipv6 input filter rule 30 destination port 546
set firewall ipv6 input filter rule 30 description 'DHCPv6 client'

# ========================================
# Phase 4: ルーティング
# ========================================

# IPv4デフォルト → WXR
set protocols static route 0.0.0.0/0 next-hop 192.168.100.1

# IPv6デフォルト → NGN
set protocols static route6 ::/0 next-hop fe80::a611:bbff:fe7d:ee11 interface eth1

# ========================================
# Phase 4: NAT設定
# ========================================

set nat source rule 100 outbound-interface name eth0
set nat source rule 100 source address 192.168.1.0/24
set nat source rule 100 translation address masquerade

# ========================================
# 適用
# ========================================

echo "Initial setup completed. Run 'commit' and 'save' to apply."

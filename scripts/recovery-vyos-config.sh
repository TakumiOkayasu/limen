#!/bin/bash
# VyOS復旧スクリプト
# 用途: VyOSが起動しない/設定が吹き飛んだ場合の復旧手順
#
# 使い方:
#   1. VyOSを新規インストール
#   2. このスクリプトをVyOSにscpで転送
#   3. bash recovery-vyos-config.sh を実行

set -e

echo "=== VyOS Recovery Script ==="
echo "このスクリプトはVyOSの基本設定を復旧します"
echo ""

# VyOS設定モードで実行する必要がある
if [ ! -f /bin/vbash ]; then
    echo "ERROR: VyOS環境ではありません"
    exit 1
fi

# 設定コマンドを生成
cat << 'VYOS_CONFIG'
# ============================================
# VyOS復旧コマンド
# VyOSにログイン後、以下を実行してください
# ============================================

configure

# --- 基本設定 ---
set system host-name 'vyos-router'
set system time-zone 'Asia/Tokyo'
set system ntp server ntp.nict.jp
set system ntp server ntp.jst.mfeed.ad.jp

# --- インターフェース設定 ---
# eth0: WXR接続用 (MAP-E upstream)
set interfaces ethernet eth0 address '192.168.100.2/24'
set interfaces ethernet eth0 description 'To WXR LAN (MAP-E upstream)'

# eth1: WAN (IPoE/IPv6)
set interfaces ethernet eth1 description 'WAN'
set interfaces ethernet eth1 ipv6 address autoconf

# eth2: LAN
set interfaces ethernet eth2 address '192.168.1.1/24'
set interfaces ethernet eth2 description 'LAN'

# --- SSH設定 ---
set service ssh listen-address '192.168.1.1'
set service ssh port '22'

# --- SSH公開鍵 (ed25519) ---
# 注意: 以下は例です。実際の公開鍵に置き換えてください
# set system login user vyos authentication public-keys your-key-name type ssh-ed25519
# set system login user vyos authentication public-keys your-key-name key 'AAAA...'

# --- ファイアウォール IPv6 input filter ---
set firewall ipv6 input filter default-action 'drop'
set firewall ipv6 input filter rule 10 action 'accept'
set firewall ipv6 input filter rule 10 state 'established'
set firewall ipv6 input filter rule 10 state 'related'
set firewall ipv6 input filter rule 20 action 'accept'
set firewall ipv6 input filter rule 20 protocol 'ipv6-icmp'
set firewall ipv6 input filter rule 30 action 'accept'
set firewall ipv6 input filter rule 30 destination port '546'
set firewall ipv6 input filter rule 30 protocol 'udp'
set firewall ipv6 input filter rule 30 source port '547'

# --- ファイアウォール IPv6 forward filter ---
set firewall ipv6 forward filter default-action 'drop'
set firewall ipv6 forward filter rule 10 action 'accept'
set firewall ipv6 forward filter rule 10 state 'established'
set firewall ipv6 forward filter rule 10 state 'related'
set firewall ipv6 forward filter rule 10 inbound-interface name 'eth1'
set firewall ipv6 forward filter rule 20 action 'accept'
set firewall ipv6 forward filter rule 20 inbound-interface name 'eth1'
set firewall ipv6 forward filter rule 20 protocol 'ipv6-icmp'
set firewall ipv6 forward filter rule 21 action 'accept'
set firewall ipv6 forward filter rule 21 inbound-interface name 'eth1'
set firewall ipv6 forward filter rule 21 state 'new'
set firewall ipv6 forward filter rule 21 destination group network-group 'LAN-v6'
set firewall ipv6 forward filter rule 100 action 'accept'
set firewall ipv6 forward filter rule 100 outbound-interface name 'eth1'

# --- IPv4 ルーティング (WXR経由) ---
set protocols static route 0.0.0.0/0 next-hop 192.168.100.1

# --- NAT (IPv4, LAN -> WXR) ---
set nat source rule 100 outbound-interface name 'eth0'
set nat source rule 100 source address '192.168.1.0/24'
set nat source rule 100 translation address 'masquerade'

commit
save

# ============================================
# 復旧完了後の確認コマンド
# ============================================
# show interfaces
# ping 192.168.100.1  (WXRへの疎通)
# ping6 google.com    (IPv6インターネット)

VYOS_CONFIG

echo ""
echo "上記のコマンドをVyOSで実行してください"
echo ""
echo "=== 追加手順 ==="
echo "1. SSH公開鍵を設定する場合:"
echo "   set system login user vyos authentication public-keys <name> type ssh-ed25519"
echo "   set system login user vyos authentication public-keys <name> key '<公開鍵>'"
echo ""
echo "2. DHCPv6-PDを使用する場合 (VyOSでIPv6プレフィックスを取得):"
echo "   set interfaces ethernet eth1 address 'dhcpv6'"
echo "   set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:<MAC>'"
echo "   set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id '1'"
echo "   set interfaces ethernet eth1 dhcpv6-options pd 0 length '56'"
echo ""

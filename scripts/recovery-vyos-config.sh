#!/bin/bash
# ============================================
# VyOS 設定復元スクリプト
# 更新日: 2026-01-14
# ============================================
#
# 用途: VyOSが起動しない/設定が吹き飛んだ場合の復旧手順
#
# 使い方:
#   1. VyOSカスタムISO (r8126対応) で新規インストール
#   2. コンソールで最小限の設定 (STEP 1)
#   3. SSH接続して残りの設定を投入
#
# 注意:
# - このスクリプトは直接実行しない (手順表示用)
# - 各STEPをconfigureモードでコピペして実行
# - シークレット値 (WireGuard鍵、Cloudflare API等) は別途入力が必要

set -e

cat << 'EOF'
============================================
VyOS 設定復元手順 (2026-01-14更新)
============================================

【シークレット値の場所】
  - SSH公開鍵: ~/.ssh/id_ed25519-touch-id.pub
  - WireGuard鍵: ~/.wireguard/
  - Cloudflare APIトークン: Cloudflareダッシュボード

============================================
STEP 1: 最小限の設定 (コンソールで実行)
============================================

configure

# ホスト名・タイムゾーン
set system host-name 'vyos-router'
set system time-zone 'Asia/Tokyo'

# NTP
set service ntp server ntp.nict.jp
set service ntp server ntp.jst.mfeed.ad.jp
set service ntp allow-client address '192.168.0.0/16'
set service ntp allow-client address 'fc00::/7'

# LAN側IP (SSH用)
set interfaces ethernet eth2 address '192.168.1.1/24'
set interfaces ethernet eth2 description 'LAN'

# SSH有効化
set service ssh listen-address '192.168.1.1'
set service ssh port '22'

commit
save
exit

# → Macから ssh vyos@192.168.1.1 で接続テスト

============================================
STEP 2: SSH公開鍵登録
============================================
# [Mac] cat ~/.ssh/id_ed25519-touch-id.pub でkeyを確認

configure

set system login user vyos authentication public-keys macbook type ssh-ed25519
set system login user vyos authentication public-keys macbook key '<公開鍵のAAAA...部分>'

commit
save

# → 別ターミナルで接続テスト後:
set service ssh disable-password-authentication
commit
save

============================================
STEP 3: WAN側 (eth1) + DHCPv6-PD
============================================

configure

set interfaces ethernet eth1 description 'WAN'
set interfaces ethernet eth1 ipv6 address autoconf
set interfaces ethernet eth1 offload gro
set interfaces ethernet eth1 offload gso
set interfaces ethernet eth1 offload sg
set interfaces ethernet eth1 offload tso

# DHCPv6-PD (DUID-LL形式必須)
# eth1 MAC: c4:62:37:08:0e:53
set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:c4:62:37:08:0e:53'
set interfaces ethernet eth1 dhcpv6-options pd 0 length '56'
set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id '1'

commit
save

============================================
STEP 4: LAN側RA配布
============================================

configure

set service router-advert interface eth2 prefix 2404:7a82:4d02:4101::/64
set service router-advert interface eth2 name-server 2606:4700:4700::1111
set service router-advert interface eth2 name-server 2606:4700:4700::1001
set service router-advert interface eth2 name-server 2001:4860:4860::8888

commit
save

============================================
STEP 5: WXR接続 (eth0) + IPv4ルーティング
============================================

configure

set interfaces ethernet eth0 description 'To WXR LAN (IPv4 transit)'
set interfaces ethernet eth0 address '192.168.100.2/24'

set protocols static route 0.0.0.0/0 next-hop 192.168.100.1

set nat source rule 100 outbound-interface name 'eth0'
set nat source rule 100 source address '192.168.1.0/24'
set nat source rule 100 translation address 'masquerade'

commit
save

============================================
STEP 6: IPv6 input filter
============================================

configure

set firewall ipv6 input filter default-action 'drop'
set firewall ipv6 input filter default-log

set firewall ipv6 input filter rule 10 action 'accept'
set firewall ipv6 input filter rule 10 state 'established'
set firewall ipv6 input filter rule 10 state 'related'

set firewall ipv6 input filter rule 20 action 'accept'
set firewall ipv6 input filter rule 20 protocol 'ipv6-icmp'

set firewall ipv6 input filter rule 30 action 'accept'
set firewall ipv6 input filter rule 30 destination port '546'
set firewall ipv6 input filter rule 30 protocol 'udp'
set firewall ipv6 input filter rule 30 source port '547'

set firewall ipv6 input filter rule 40 action 'drop'
set firewall ipv6 input filter rule 40 protocol 'udp'
set firewall ipv6 input filter rule 40 destination port '51820'
set firewall ipv6 input filter rule 40 recent count '10'
set firewall ipv6 input filter rule 40 recent time 'minute'
set firewall ipv6 input filter rule 40 state 'new'
set firewall ipv6 input filter rule 40 log
set firewall ipv6 input filter rule 40 description 'Rate limit WireGuard'

set firewall ipv6 input filter rule 50 action 'accept'
set firewall ipv6 input filter rule 50 protocol 'udp'
set firewall ipv6 input filter rule 50 destination port '51820'
set firewall ipv6 input filter rule 50 description 'Allow WireGuard'

commit
save

============================================
STEP 7: IPv6 forward filter
============================================

configure

set firewall ipv6 forward filter default-action 'drop'
set firewall ipv6 forward filter default-log

set firewall ipv6 forward filter rule 10 action 'accept'
set firewall ipv6 forward filter rule 10 state 'established'
set firewall ipv6 forward filter rule 10 state 'related'
set firewall ipv6 forward filter rule 10 inbound-interface name 'eth1'

set firewall ipv6 forward filter rule 20 action 'accept'
set firewall ipv6 forward filter rule 20 protocol 'icmpv6'
set firewall ipv6 forward filter rule 20 icmpv6 type-name 'echo-request'
set firewall ipv6 forward filter rule 20 inbound-interface name 'eth1'

set firewall ipv6 forward filter rule 21 action 'accept'
set firewall ipv6 forward filter rule 21 protocol 'icmpv6'
set firewall ipv6 forward filter rule 21 icmpv6 type-name 'nd-neighbor-solicit'
set firewall ipv6 forward filter rule 21 inbound-interface name 'eth1'

set firewall ipv6 forward filter rule 22 action 'accept'
set firewall ipv6 forward filter rule 22 protocol 'icmpv6'
set firewall ipv6 forward filter rule 22 icmpv6 type-name 'nd-neighbor-advert'
set firewall ipv6 forward filter rule 22 inbound-interface name 'eth1'

set firewall ipv6 forward filter rule 23 action 'accept'
set firewall ipv6 forward filter rule 23 protocol 'icmpv6'
set firewall ipv6 forward filter rule 23 icmpv6 type-name 'nd-router-solicit'
set firewall ipv6 forward filter rule 23 inbound-interface name 'eth1'

set firewall ipv6 forward filter rule 24 action 'accept'
set firewall ipv6 forward filter rule 24 protocol 'icmpv6'
set firewall ipv6 forward filter rule 24 icmpv6 type-name 'nd-router-advert'
set firewall ipv6 forward filter rule 24 inbound-interface name 'eth1'

set firewall ipv6 forward filter rule 90 action 'drop'
set firewall ipv6 forward filter rule 90 inbound-interface name 'wg0'
set firewall ipv6 forward filter rule 90 outbound-interface name 'eth2'
set firewall ipv6 forward filter rule 90 description 'Block VPN to LAN'

set firewall ipv6 forward filter rule 91 action 'drop'
set firewall ipv6 forward filter rule 91 inbound-interface name 'wg0'
set firewall ipv6 forward filter rule 91 outbound-interface name 'eth1'
set firewall ipv6 forward filter rule 91 description 'Block VPN to WAN'

set firewall ipv6 forward filter rule 100 action 'accept'
set firewall ipv6 forward filter rule 100 outbound-interface name 'eth1'

commit
save

============================================
STEP 8: IPv4 forward filter
============================================

configure

set firewall ipv4 forward filter default-action 'accept'

set firewall ipv4 forward filter rule 90 action 'drop'
set firewall ipv4 forward filter rule 90 inbound-interface name 'wg0'
set firewall ipv4 forward filter rule 90 outbound-interface name 'eth2'
set firewall ipv4 forward filter rule 90 description 'Block VPN to LAN'

set firewall ipv4 forward filter rule 91 action 'drop'
set firewall ipv4 forward filter rule 91 inbound-interface name 'wg0'
set firewall ipv4 forward filter rule 91 outbound-interface name 'eth1'
set firewall ipv4 forward filter rule 91 description 'Block VPN to WAN'

commit
save

============================================
STEP 9: WireGuard VPN
============================================
# 鍵生成: run generate pki wireguard key-pair

configure

set interfaces wireguard wg0 address '10.10.10.1/24'
set interfaces wireguard wg0 address 'fd00:10:10:10::1/64'
set interfaces wireguard wg0 port '51820'
set interfaces wireguard wg0 private-key '<VyOS秘密鍵>'

set interfaces wireguard wg0 peer mac allowed-ips '10.10.10.2/32'
set interfaces wireguard wg0 peer mac allowed-ips 'fd00:10:10:10::2/128'
set interfaces wireguard wg0 peer mac public-key '<Mac公開鍵>'

set interfaces wireguard wg0 peer iphone allowed-ips '10.10.10.3/32'
set interfaces wireguard wg0 peer iphone allowed-ips 'fd00:10:10:10::3/128'
set interfaces wireguard wg0 peer iphone public-key '<iPhone公開鍵>'

commit
save

# クライアント設定の PublicKey を新VyOS公開鍵に更新すること

============================================
STEP 10: Cloudflare DDNS
============================================

configure

set service dns dynamic name cloudflare address interface 'eth1'
set service dns dynamic name cloudflare protocol 'cloudflare'
set service dns dynamic name cloudflare zone 'murata-lab.net'
set service dns dynamic name cloudflare host-name 'router.murata-lab.net'
set service dns dynamic name cloudflare password '<Cloudflare APIトークン>'
set service dns dynamic name cloudflare ip-version 'ipv6'

commit
save

============================================
STEP 11: システム設定
============================================

configure

set system config-management commit-revisions '100'
set system console device ttyS0 speed '115200'
set system syslog local facility all level 'info'
set system syslog local facility local7 level 'debug'

commit
save

============================================
STEP 12: 自動バックアップ
============================================

sudo mkdir -p /config/backup /config/scripts

cat << 'SCRIPT' | sudo tee /config/scripts/backup.sh
#!/bin/bash
BACKUP_DIR="/config/backup"
DATE=$(date +%Y%m%d)
MAX_BACKUPS=30
cp /config/config.boot "${BACKUP_DIR}/config-${DATE}.boot"
find "${BACKUP_DIR}" -name "config-*.boot" -mtime +${MAX_BACKUPS} -delete
SCRIPT

sudo chmod +x /config/scripts/backup.sh

configure
set system task-scheduler task daily-backup crontab-spec '0 3 * * *'
set system task-scheduler task daily-backup executable path '/config/scripts/backup.sh'
commit
save

============================================
STEP 13: r8126モジュール確認
============================================

sudo modprobe r8126
show interfaces

============================================
動作確認
============================================

ping6 2001:4860:4860::8888
ping 8.8.8.8
show interfaces
show firewall
show interfaces wireguard
show dns dynamic status

EOF

echo ""
echo "復元完了後、クライアント側のWireGuard設定を更新してください。"
echo "  Endpoint: router.murata-lab.net:51820"
echo "  PublicKey: <新しいVyOS公開鍵>"

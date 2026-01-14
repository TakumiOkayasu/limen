#!/bin/bash
# ============================================
# VyOS復元スクリプト生成ツール
# ============================================
#
# 使い方:
#   1. vyos-restore.env を作成して値を設定
#   2. ./generate-vyos-restore.sh を実行
#   3. 生成された vyos-restore.vbash を VyOS に転送
#   4. VyOS で実行: vbash /tmp/vyos-restore.vbash
#
# 出力: vyos-restore.vbash (VyOS用設定スクリプト)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/vyos-restore.env"
OUTPUT_FILE="${SCRIPT_DIR}/vyos-restore.vbash"

# 環境変数ファイル読み込み
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: ${ENV_FILE} が見つかりません"
    echo "cp vyos-restore.env.example vyos-restore.env で作成してください"
    exit 1
fi

source "$ENV_FILE"

# 必須項目チェック
MISSING=""
[ -z "$SSH_PUBKEY" ] && MISSING="${MISSING} SSH_PUBKEY"
[ -z "$WIREGUARD_SERVER_PRIVKEY" ] && MISSING="${MISSING} WIREGUARD_SERVER_PRIVKEY"
[ -z "$WIREGUARD_MAC_PUBKEY" ] && MISSING="${MISSING} WIREGUARD_MAC_PUBKEY"
[ -z "$WIREGUARD_IPHONE_PUBKEY" ] && MISSING="${MISSING} WIREGUARD_IPHONE_PUBKEY"
[ -z "$CLOUDFLARE_API_TOKEN" ] && MISSING="${MISSING} CLOUDFLARE_API_TOKEN"

if [ -n "$MISSING" ]; then
    echo "ERROR: 以下の環境変数が未設定です:"
    echo " $MISSING"
    echo ""
    echo "vyos-restore.env を編集して設定してください"
    exit 1
fi

echo "VyOS復元スクリプトを生成中..."

cat > "$OUTPUT_FILE" << 'SCRIPT_HEADER'
#!/bin/vbash
# ============================================
# VyOS 一括復元スクリプト (自動生成)
# ============================================
# 生成日: GENERATED_DATE
#
# 使い方:
#   1. このファイルを VyOS に転送: scp vyos-restore.vbash vyos@192.168.1.1:/tmp/
#   2. VyOS で実行: vbash /tmp/vyos-restore.vbash
#
# 注意:
#   - 最小限の設定 (STEP 1) 完了後に実行すること
#   - SSH接続可能な状態で実行すること

source /opt/vyatta/etc/functions/script-template

echo "=== VyOS 一括復元開始 ==="

configure

# ============================================
# 基本設定
# ============================================
echo "[1/12] 基本設定..."
set system host-name 'vyos-router'
set system time-zone 'Asia/Tokyo'
set service ntp server ntp.nict.jp
set service ntp server ntp.jst.mfeed.ad.jp

# ============================================
# SSH公開鍵
# ============================================
echo "[2/12] SSH公開鍵..."
SCRIPT_HEADER

# SSH公開鍵を挿入
cat >> "$OUTPUT_FILE" << EOF
set system login user vyos authentication public-keys macbook type ${SSH_PUBKEY_TYPE}
set system login user vyos authentication public-keys macbook key '${SSH_PUBKEY}'
set service ssh disable-password-authentication
EOF

cat >> "$OUTPUT_FILE" << 'SCRIPT_INTERFACES'

# ============================================
# インターフェース設定
# ============================================
echo "[3/12] インターフェース設定..."

# eth0: WXR接続
set interfaces ethernet eth0 description 'To WXR LAN (IPv4 transit)'
set interfaces ethernet eth0 address '192.168.100.2/24'

# eth1: WAN
set interfaces ethernet eth1 description 'WAN'
set interfaces ethernet eth1 ipv6 address autoconf
set interfaces ethernet eth1 offload gro
set interfaces ethernet eth1 offload gso
set interfaces ethernet eth1 offload sg
set interfaces ethernet eth1 offload tso

# DHCPv6-PD (DUID-LL形式)
set interfaces ethernet eth1 dhcpv6-options duid '00:03:00:01:c4:62:37:08:0e:53'
set interfaces ethernet eth1 dhcpv6-options pd 0 length '56'
set interfaces ethernet eth1 dhcpv6-options pd 0 interface eth2 sla-id '1'

# eth2: LAN
set interfaces ethernet eth2 address '192.168.1.1/24'
set interfaces ethernet eth2 description 'LAN'

# ============================================
# RA配布 (LAN側)
# ============================================
echo "[4/12] RA配布設定..."
set service router-advert interface eth2 prefix 2404:7a82:4d02:4101::/64
set service router-advert interface eth2 name-server 2606:4700:4700::1111
set service router-advert interface eth2 name-server 2606:4700:4700::1001
set service router-advert interface eth2 name-server 2001:4860:4860::8888

# ============================================
# IPv4ルーティング + NAT
# ============================================
echo "[5/12] IPv4ルーティング..."
set protocols static route 0.0.0.0/0 next-hop 192.168.100.1

set nat source rule 100 outbound-interface name 'eth0'
set nat source rule 100 source address '192.168.1.0/24'
set nat source rule 100 translation address 'masquerade'

# ============================================
# IPv6 input filter
# ============================================
echo "[6/12] IPv6 input filter..."
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

# ============================================
# IPv6 forward filter
# ============================================
echo "[7/12] IPv6 forward filter..."
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

# ============================================
# IPv4 forward filter
# ============================================
echo "[8/12] IPv4 forward filter..."
set firewall ipv4 forward filter default-action 'accept'

set firewall ipv4 forward filter rule 90 action 'drop'
set firewall ipv4 forward filter rule 90 inbound-interface name 'wg0'
set firewall ipv4 forward filter rule 90 outbound-interface name 'eth2'
set firewall ipv4 forward filter rule 90 description 'Block VPN to LAN'

set firewall ipv4 forward filter rule 91 action 'drop'
set firewall ipv4 forward filter rule 91 inbound-interface name 'wg0'
set firewall ipv4 forward filter rule 91 outbound-interface name 'eth1'
set firewall ipv4 forward filter rule 91 description 'Block VPN to WAN'

# ============================================
# WireGuard VPN
# ============================================
echo "[9/12] WireGuard VPN..."
set interfaces wireguard wg0 address '10.10.10.1/24'
set interfaces wireguard wg0 address 'fd00:10:10:10::1/64'
set interfaces wireguard wg0 port '51820'
SCRIPT_INTERFACES

# WireGuard秘密鍵・公開鍵を挿入
cat >> "$OUTPUT_FILE" << EOF
set interfaces wireguard wg0 private-key '${WIREGUARD_SERVER_PRIVKEY}'

set interfaces wireguard wg0 peer mac allowed-ips '10.10.10.2/32'
set interfaces wireguard wg0 peer mac allowed-ips 'fd00:10:10:10::2/128'
set interfaces wireguard wg0 peer mac public-key '${WIREGUARD_MAC_PUBKEY}'

set interfaces wireguard wg0 peer iphone allowed-ips '10.10.10.3/32'
set interfaces wireguard wg0 peer iphone allowed-ips 'fd00:10:10:10::3/128'
set interfaces wireguard wg0 peer iphone public-key '${WIREGUARD_IPHONE_PUBKEY}'
EOF

cat >> "$OUTPUT_FILE" << 'SCRIPT_DDNS'

# ============================================
# Cloudflare DDNS
# ============================================
echo "[10/12] Cloudflare DDNS..."
set service dns dynamic name cloudflare address interface 'eth1'
set service dns dynamic name cloudflare protocol 'cloudflare'
set service dns dynamic name cloudflare zone 'murata-lab.net'
set service dns dynamic name cloudflare host-name 'router.murata-lab.net'
SCRIPT_DDNS

# Cloudflare APIトークンを挿入
cat >> "$OUTPUT_FILE" << EOF
set service dns dynamic name cloudflare password '${CLOUDFLARE_API_TOKEN}'
EOF

cat >> "$OUTPUT_FILE" << 'SCRIPT_FOOTER'
set service dns dynamic name cloudflare ip-version 'ipv6'

# ============================================
# 自動バックアップ
# ============================================
echo "[11/12] 自動バックアップ設定..."
set system task-scheduler task daily-backup crontab-spec '0 3 * * *'
set system task-scheduler task daily-backup executable path '/config/scripts/backup.sh'

# ============================================
# 設定を適用・保存
# ============================================
echo "[12/12] 設定を適用・保存..."
commit
save

echo ""
echo "=== VyOS 一括復元完了 ==="
echo ""
echo "次のステップ:"
echo "  1. exit で設定モードを抜ける"
echo "  2. バックアップスクリプト作成:"
echo "     sudo mkdir -p /config/backup /config/scripts"
echo "     cat << 'SCRIPT' | sudo tee /config/scripts/backup.sh"
echo "     #!/bin/bash"
echo "     BACKUP_DIR=\"/config/backup\""
echo "     DATE=\$(date +%Y%m%d)"
echo "     MAX_BACKUPS=30"
echo "     cp /config/config.boot \"\${BACKUP_DIR}/config-\${DATE}.boot\""
echo "     find \"\${BACKUP_DIR}\" -name \"config-*.boot\" -mtime +\${MAX_BACKUPS} -delete"
echo "     SCRIPT"
echo "     sudo chmod +x /config/scripts/backup.sh"
echo ""
echo "  3. 動作確認:"
echo "     ping6 2001:4860:4860::8888"
echo "     ping 8.8.8.8"
echo "     show interfaces"
echo "     show dns dynamic status"
SCRIPT_FOOTER

# 生成日を置換
sed -i '' "s/GENERATED_DATE/$(date +%Y-%m-%d)/" "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"

echo ""
echo "=== 生成完了 ==="
echo "出力: ${OUTPUT_FILE}"
echo ""
echo "次のステップ:"
echo "  1. VyOSで最小限の設定を完了 (SSH接続可能に)"
echo "  2. scp ${OUTPUT_FILE} vyos@192.168.1.1:/tmp/"
echo "  3. VyOSで: vbash /tmp/vyos-restore.vbash"

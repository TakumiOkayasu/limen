#!/bin/bash
# MAP-Eトンネル設定スクリプト
# 使用方法: sudo ./setup-mape.sh
#
# このスクリプトは以下を設定します:
# 1. DHCPv6 DUID-LLファイル
# 2. MAP-Eトンネル (起動スクリプト)
# 3. VyOS設定 (CEアドレス、BRルート、NAT)

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# パラメータ
ETH1_MAC="c4:62:37:08:0e:53"
CE_ADDRESS="2404:7a82:4d02:4100:85:d10d:200:4100"
BR_ADDRESS="2001:260:700:1::1:275"
IPV4_ADDRESS="133.209.13.2"
NGN_GATEWAY="fe80::a611:bbff:fe7d:ee11"
PORT_RANGE="5136-5151"

BOOTUP_SCRIPT="/config/scripts/vyos-preconfig-bootup.script"

# root権限チェック
if [ "$EUID" -ne 0 ]; then
    echo_error "root権限で実行してください: sudo $0"
    exit 1
fi

echo "========================================"
echo "  MAP-E トンネル設定スクリプト"
echo "========================================"
echo ""
echo "パラメータ:"
echo "  CE Address: $CE_ADDRESS"
echo "  BR Address: $BR_ADDRESS"
echo "  IPv4 Address: $IPV4_ADDRESS"
echo "  Port Range: $PORT_RANGE"
echo ""
read -p "続行しますか? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "キャンセルしました"
    exit 0
fi

# 1. DHCPv6 DUID-LLファイル作成
echo_info "DHCPv6 DUID-LLファイルを作成中..."
mkdir -p /var/lib/dhcpv6
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' > /var/lib/dhcpv6/dhcp6c_duid
echo_info "DUID-LLファイル作成完了"

# 2. 起動スクリプトにMAP-E設定を追加
echo_info "起動スクリプトを更新中..."

# 既存のMAP-E設定があれば削除
if grep -q "MAP-Eトンネル設定" "$BOOTUP_SCRIPT" 2>/dev/null; then
    echo_warn "既存のMAP-E設定を削除します"
    sed -i '/# MAP-Eトンネル設定/,/ip route add default dev mape/d' "$BOOTUP_SCRIPT"
fi

# 既存のDUID設定があれば削除
if grep -q "DHCPv6 DUID-LL" "$BOOTUP_SCRIPT" 2>/dev/null; then
    echo_warn "既存のDUID設定を削除します"
    sed -i '/# DHCPv6 DUID-LL/,/dhcp6c_duid/d' "$BOOTUP_SCRIPT"
fi

# スクリプトがなければ作成
if [ ! -f "$BOOTUP_SCRIPT" ]; then
    cat > "$BOOTUP_SCRIPT" << 'HEADER'
#!/bin/sh
# This script is executed at boot time before VyOS configuration is applied.
# Any modifications required to work around unfixed bugs or use
# services not available through the VyOS CLI system can be placed here.

HEADER
    chmod +x "$BOOTUP_SCRIPT"
fi

# DUID設定を追加
cat >> "$BOOTUP_SCRIPT" << EOF

# DHCPv6 DUID-LL形式を強制設定 (NGN対応)
# eth1のMACアドレス: $ETH1_MAC
# NGNはDUID-LL形式のみ受け付ける (DUID-LLT, DUID-UUIDは無視される)
mkdir -p /var/lib/dhcpv6
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' > /var/lib/dhcpv6/dhcp6c_duid
EOF

# MAP-E設定を追加
cat >> "$BOOTUP_SCRIPT" << EOF

# MAP-Eトンネル設定 (VyOSネイティブ設定が動作しないためのワークアラウンド)
# TODO: VyOS tun0設定が動作しない原因を調査し、解決したらこのスクリプトを削除する
ip -6 tunnel add mape mode ip4ip6 remote $BR_ADDRESS local $CE_ADDRESS dev eth1
ip addr add $IPV4_ADDRESS/32 dev mape
ip link set mape up
ip route add default dev mape
EOF

echo_info "起動スクリプト更新完了"

# 3. VyOS設定
echo_info "VyOS設定を適用中..."

# 設定モードでコマンドを実行
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper begin

# CEアドレスをeth1に追加
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces ethernet eth1 address "$CE_ADDRESS/64" 2>/dev/null || true

# BRへのルート
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set protocols static route6 "$BR_ADDRESS/128" next-hop "$NGN_GATEWAY" interface eth1 2>/dev/null || true

# NAT設定
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 outbound-interface name tun0 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 translation address "$IPV4_ADDRESS" 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 translation port "$PORT_RANGE" 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 protocol tcp_udp 2>/dev/null || true

# WXR経由のデフォルトルートがあれば削除
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper delete protocols static route 0.0.0.0/0 next-hop 192.168.100.1 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper delete protocols static route 0.0.0.0/0 interface tun0 2>/dev/null || true

/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper commit
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper save
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper end

echo_info "VyOS設定完了"

# 4. 現在のセッションでMAP-Eを有効化
echo_info "MAP-Eトンネルを作成中..."

# 既存のmapeがあれば削除
ip link del mape 2>/dev/null || true

ip -6 tunnel add mape mode ip4ip6 remote "$BR_ADDRESS" local "$CE_ADDRESS" dev eth1
ip addr add "$IPV4_ADDRESS/32" dev mape
ip link set mape up
ip route add default dev mape 2>/dev/null || true

echo_info "MAP-Eトンネル作成完了"

# 5. 動作確認
echo ""
echo "========================================"
echo "  設定完了 - 動作確認"
echo "========================================"
echo ""
echo "トンネル状態:"
ip link show mape
echo ""
echo "デフォルトルート:"
ip route show default
echo ""
echo "IPv4疎通テスト..."
if curl -4 -s -I --max-time 5 https://www.google.com | head -1 | grep -q "200"; then
    echo_info "IPv4疎通: 成功"
else
    echo_error "IPv4疎通: 失敗"
    echo_warn "再起動後に確認してください: sudo reboot"
fi

echo ""
echo "========================================"
echo "  完了"
echo "========================================"
echo ""
echo "注意: pingはMAP-Eポート制限のため動作しません。"
echo "      IPv4疎通確認にはcurlを使用してください。"
echo ""

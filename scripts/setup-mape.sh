#!/bin/bash
# MAP-Eトンネル設定スクリプト (VyOSネイティブ版)
# 使用方法: sudo ./setup-mape.sh
#
# このスクリプトは以下を設定します:
# 1. DHCPv6 DUID-LLファイル (起動スクリプト)
# 2. VyOS設定 (CEアドレス、BRルート、tun0トンネル、NAT)

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
echo "  (VyOSネイティブ設定版)"
echo "========================================"
echo ""
echo "前提条件:"
echo "  - WXRがAPモードであること (ルーターモードは競合する)"
echo "  - eth1がONUに直結されていること"
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

# 1. 起動スクリプト (DUID-LL設定のみ)
echo_info "起動スクリプトを設定中..."

cat > "$BOOTUP_SCRIPT" << 'EOF'
#!/bin/sh
# This script is executed at boot time before VyOS configuration is applied.

# DHCPv6 DUID-LL形式を強制設定 (NGN対応)
# NGNはDUID-LL形式のみ受け付ける
mkdir -p /var/lib/dhcpv6
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' > /var/lib/dhcpv6/dhcp6c_duid
EOF
chmod +x "$BOOTUP_SCRIPT"

# 現在のセッションでもDUID設定
mkdir -p /var/lib/dhcpv6
printf '\x0a\x00\x00\x03\x00\x01\xc4\x62\x37\x08\x0e\x53' > /var/lib/dhcpv6/dhcp6c_duid

echo_info "起動スクリプト設定完了"

# 2. VyOS設定
echo_info "VyOS設定を適用中..."

/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper begin

# eth1にCEアドレスを追加
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces ethernet eth1 address "$CE_ADDRESS/64" 2>/dev/null || true

# BRへの静的ルート
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set protocols static route6 "$BR_ADDRESS/128" next-hop "$NGN_GATEWAY" interface eth1 2>/dev/null || true

# MAP-Eトンネル (VyOSネイティブ設定)
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces tunnel tun0 encapsulation ipip6 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces tunnel tun0 source-address "$CE_ADDRESS" 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces tunnel tun0 remote "$BR_ADDRESS" 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces tunnel tun0 source-interface eth1 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces tunnel tun0 address "$IPV4_ADDRESS/32" 2>/dev/null || true

# デフォルトルート
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set protocols static route 0.0.0.0/0 interface tun0 2>/dev/null || true

# NAT設定 (source addressは指定しない - VyOS自身の通信もNATするため)
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 outbound-interface name tun0 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 protocol tcp_udp 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 translation address "$IPV4_ADDRESS" 2>/dev/null || true
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 200 translation port "$PORT_RANGE" 2>/dev/null || true

# 古いmape用NATルールがあれば削除
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper delete nat source rule 210 2>/dev/null || true

/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper commit
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper save
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper end

echo_info "VyOS設定完了"

# 3. 動作確認
echo ""
echo "========================================"
echo "  設定完了 - 動作確認"
echo "========================================"
echo ""
echo "トンネル状態:"
ip link show tun0 2>/dev/null || echo "tun0が見つかりません (再起動が必要かもしれません)"
echo ""
echo "デフォルトルート:"
ip route show default
echo ""
echo "IPv4疎通テスト..."
if curl -4 -s -I --max-time 5 https://www.google.com | head -1 | grep -q "200"; then
    echo_info "IPv4疎通: 成功"
else
    echo_error "IPv4疎通: 失敗"
    echo_warn "確認事項:"
    echo_warn "  1. WXRがAPモードになっているか"
    echo_warn "  2. eth1がONUに直結されているか"
    echo_warn "  3. 再起動: sudo reboot"
fi

echo ""
echo "========================================"
echo "  完了"
echo "========================================"
echo ""
echo "注意:"
echo "  - pingはMAP-Eポート制限のため動作しません"
echo "  - IPv4疎通確認にはcurlを使用してください"
echo "  - WXRは必ずAPモードで運用してください"
echo ""

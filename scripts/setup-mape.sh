#!/bin/bash
# MAP-E トンネル設定スクリプト (VyOS用)
#
# 使用方法:
#   [VyOS] sudo /config/scripts/setup-mape.sh
#
# このスクリプトは以下を設定します:
# 1. ip6_tunnelカーネルモジュールのロード
# 2. CEアドレスをeth1に追加
# 3. MAP-Eトンネル (ip6tnl) 作成
# 4. ルーティング設定
#
# 注意: パラメータはハードコードされています。
#       DHCPv6-PDプレフィックスが変更された場合は手動更新が必要です。
#       詳細: docs/troubleshooting-mape.md
#
# NAT設定は別途VyOS configureモードで行う必要があります:
#   set nat source rule 200 outbound-interface name 'mape'
#   set nat source rule 200 translation address '<IPV4_ADDRESS>'
#   set nat source rule 200 translation port '<PORT_RANGE>'
#   set nat source rule 200 protocol 'tcp_udp'

set -e

# 色付き出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# MAP-E パラメータ (.envから読み込み)
# ============================================================
# これらの値はDHCPv6-PDプレフィックスから計算されています。
# 計算ツール: http://ipv4.web.fc2.com/map-e.html
#
# 設定手順:
# 1. setup-mape.env.example を setup-mape.env にコピー
# 2. eth1のIPv6プレフィックスを確認: show interfaces ethernet eth1
# 3. 上記ツールでプレフィックスを入力しMAP-Eパラメータを取得
# 4. setup-mape.env に値を記入

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/setup-mape.env"

if [ ! -f "$ENV_FILE" ]; then
    echo_error ".envファイルが見つかりません: $ENV_FILE"
    echo_error "setup-mape.env.example をコピーして値を設定してください"
    exit 1
fi

# shellcheck source=/dev/null
. "$ENV_FILE"

# 必須パラメータチェック
MISSING=0
for var in MAPE_CE_ADDRESS MAPE_BR_ADDRESS MAPE_IPV4_ADDRESS MAPE_NGN_GATEWAY MAPE_FIRST_PORT_RANGE; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo_error "未設定: $var"
        MISSING=1
    fi
done
if [ "$MISSING" -eq 1 ]; then
    echo_error "$ENV_FILE に全てのパラメータを設定してください"
    exit 1
fi

CE_ADDRESS="$MAPE_CE_ADDRESS"
BR_ADDRESS="$MAPE_BR_ADDRESS"
IPV4_ADDRESS="$MAPE_IPV4_ADDRESS"
NGN_GATEWAY="$MAPE_NGN_GATEWAY"
FIRST_PORT_RANGE="$MAPE_FIRST_PORT_RANGE"

# ============================================================
# 前提条件チェック
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo_error "root権限で実行してください: sudo $0"
    exit 1
fi

if ! ip link show eth1 &>/dev/null; then
    echo_error "eth1が見つかりません"
    exit 1
fi

# ============================================================
# メイン処理
# ============================================================

echo "========================================"
echo "  MAP-E トンネル設定"
echo "========================================"
echo ""
echo "パラメータ:"
echo "  CE Address:   $CE_ADDRESS"
echo "  BR Address:   $BR_ADDRESS"
echo "  IPv4 Address: $IPV4_ADDRESS"
echo "  Port Range:   $FIRST_PORT_RANGE (NAT用)"
echo ""

# 1. カーネルモジュールロード
echo_info "ip6_tunnelモジュールをロード中..."
modprobe ip6_tunnel

# 2. CEアドレスをeth1に追加
echo_info "CEアドレスをeth1に追加中..."
if ! ip -6 addr show dev eth1 | grep -q "$CE_ADDRESS"; then
    ip -6 addr add "$CE_ADDRESS/64" dev eth1
else
    echo_info "CEアドレスは既に設定済み"
fi

# 3. 既存のmapeトンネルがあれば削除
if ip link show mape &>/dev/null; then
    echo_info "既存のmapeトンネルを削除中..."
    ip link del mape 2>/dev/null || true
fi

# 4. MAP-Eトンネル作成
echo_info "MAP-Eトンネルを作成中..."
ip -6 tunnel add mape mode ip4ip6 \
    remote "$BR_ADDRESS" \
    local "$CE_ADDRESS" \
    dev eth1

ip addr add "$IPV4_ADDRESS/32" dev mape
ip link set mape up

# 5. BRへのルート確認 (VyOS configで設定済みの想定)
echo_info "BRへのルートを確認中..."
if ! ip -6 route get "$BR_ADDRESS" | grep -q "via"; then
    echo_warn "BRへの明示的ルートがありません。追加します..."
    ip -6 route add "$BR_ADDRESS/128" via "$NGN_GATEWAY" dev eth1 2>/dev/null || true
fi

# 6. デフォルトルート設定
echo_info "デフォルトルートを設定中..."
ip route del default 2>/dev/null || true
ip route add default dev mape

# 7. rp_filter緩和 (非対称ルーティング対応)
echo_info "rp_filterを緩和中..."
echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/eth1/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/mape/rp_filter 2>/dev/null || true

echo_info "MAP-Eトンネル設定完了"

# ============================================================
# 動作確認
# ============================================================

echo ""
echo "========================================"
echo "  動作確認"
echo "========================================"
echo ""

echo "トンネル状態:"
ip link show mape
echo ""

echo "デフォルトルート:"
ip route show default
echo ""

echo "IPv4疎通テスト (curl)..."
if curl -4 -s -I --max-time 10 https://www.google.com 2>/dev/null | head -1 | grep -q "200\|301\|302"; then
    echo_info "IPv4疎通: 成功"
else
    echo_error "IPv4疎通: 失敗"
    echo ""
    echo "NAT設定を確認してください:"
    echo "  [VyOS] configure"
    echo "  [VyOS] set nat source rule 200 outbound-interface name 'mape'"
    echo "  [VyOS] set nat source rule 200 translation address '$IPV4_ADDRESS'"
    echo "  [VyOS] set nat source rule 200 translation port '$FIRST_PORT_RANGE'"
    echo "  [VyOS] set nat source rule 200 protocol 'tcp_udp'"
    echo "  [VyOS] commit"
    echo ""
    echo "詳細: docs/troubleshooting-mape.md"
fi

echo ""
echo "========================================"
echo "  完了"
echo "========================================"
echo ""
echo "注意:"
echo "  - pingはMAP-Eポート制限のため動作しません"
echo "  - IPv4疎通確認にはcurlを使用してください"
echo "  - この設定は再起動で消えます"
echo "  - 永続化: /config/scripts/vyos-preconfig-bootup.script に追加"
echo ""

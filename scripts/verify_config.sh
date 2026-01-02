#!/bin/bash
#
# VyOS設定確認スクリプト
#
# VyOS上で実行して、各Phaseの設定が正しく適用されているか確認する。
#
# 使い方:
#   scp verify_config.sh vyos:/tmp/
#   ssh vyos 'bash /tmp/verify_config.sh'

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "      $1"
}

echo "========================================"
echo " VyOS設定確認スクリプト"
echo "========================================"
echo ""

# Phase 0: 基本設定
echo "--- Phase 0: 基本設定 ---"

# タイムゾーン
if date +%Z | grep -q "JST"; then
    pass "タイムゾーン: JST"
else
    fail "タイムゾーンがJSTではありません"
    info "$(date)"
fi

# NTP
if pgrep -x "chronyd\|ntpd" > /dev/null 2>&1; then
    pass "NTPサービス稼働中"
else
    warn "NTPサービスが見つかりません"
fi

echo ""

# Phase 1: SSH
echo "--- Phase 1: SSH ---"

if systemctl is-active --quiet ssh 2>/dev/null || pgrep -x sshd > /dev/null 2>&1; then
    pass "SSHサービス稼働中"
else
    fail "SSHサービスが稼働していません"
fi

if grep -q "PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    pass "公開鍵認証が有効"
elif [ -d /config/auth/ ]; then
    # VyOS形式の設定確認
    pass "公開鍵認証が設定されています"
fi

echo ""

# Phase 2: IPv6
echo "--- Phase 2: IPv6 ---"

# WANインターフェースのIPv6
WAN_IF="${WAN_IF:-eth0}"
if ip -6 addr show dev "$WAN_IF" 2>/dev/null | grep -q "scope global"; then
    pass "WAN($WAN_IF)にグローバルIPv6アドレスあり"
    info "$(ip -6 addr show dev "$WAN_IF" | grep 'scope global' | head -1)"
else
    fail "WAN($WAN_IF)にグローバルIPv6がありません"
fi

# LANインターフェースのIPv6
LAN_IF="${LAN_IF:-eth1}"
if ip -6 addr show dev "$LAN_IF" 2>/dev/null | grep -q "scope global"; then
    pass "LAN($LAN_IF)にグローバルIPv6アドレスあり"
else
    warn "LAN($LAN_IF)にグローバルIPv6がありません(PD未取得の可能性)"
fi

# IPv6接続テスト
if ping6 -c 1 -W 3 ipv6.google.com > /dev/null 2>&1; then
    pass "IPv6インターネット接続OK"
else
    warn "IPv6インターネット接続ができません"
fi

echo ""

# Phase 3: WireGuard
echo "--- Phase 3: WireGuard ---"

if ip link show wg0 > /dev/null 2>&1; then
    pass "WireGuardインターフェース(wg0)が存在"

    # WireGuardの状態
    if command -v wg > /dev/null 2>&1; then
        PEER_COUNT=$(wg show wg0 2>/dev/null | grep -c "peer:" || echo "0")
        info "登録済みpeer数: $PEER_COUNT"
    fi
else
    warn "WireGuardインターフェースが設定されていません"
fi

# ポート待ち受け確認
WG_PORT="${WG_PORT:-51820}"
if ss -uln | grep -q ":$WG_PORT "; then
    pass "WireGuardポート($WG_PORT/UDP)がLISTEN中"
else
    warn "WireGuardポート($WG_PORT/UDP)がLISTENしていません"
fi

echo ""

# Phase 4: IPv4ルーティング
echo "--- Phase 4: IPv4ルーティング ---"

WXR_IF="${WXR_IF:-eth2}"
WXR_GW="${WXR_GW:-192.168.100.1}"

if ip addr show dev "$WXR_IF" 2>/dev/null | grep -q "inet "; then
    pass "WXR接続インターフェース($WXR_IF)にIPv4あり"
else
    warn "WXR接続インターフェース($WXR_IF)が設定されていません"
fi

# WXRへの疎通
if ping -c 1 -W 2 "$WXR_GW" > /dev/null 2>&1; then
    pass "WXR($WXR_GW)への疎通OK"
else
    warn "WXR($WXR_GW)への疎通ができません"
fi

# IPv4インターネット接続
if ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1; then
    pass "IPv4インターネット接続OK"
else
    warn "IPv4インターネット接続ができません"
fi

# デフォルトルート確認
if ip route | grep -q "default via $WXR_GW"; then
    pass "デフォルトルートがWXR経由"
elif ip route | grep -q "default.*blackhole"; then
    info "デフォルトルートがblackhole(IPv4制限モード)"
fi

echo ""

# Phase 5: DDNS
echo "--- Phase 5: DDNS ---"

if pgrep -f ddclient > /dev/null 2>&1 || systemctl is-active --quiet ddclient 2>/dev/null; then
    pass "DDNSクライアント稼働中"
else
    warn "DDNSクライアントが稼働していません"
fi

echo ""

# Phase 6: バックアップ
echo "--- Phase 6: バックアップ ---"

if [ -d /config/backup ]; then
    BACKUP_COUNT=$(ls -1 /config/backup/*.boot 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        pass "バックアップあり ($BACKUP_COUNT 件)"
        info "最新: $(ls -1t /config/backup/*.boot 2>/dev/null | head -1)"
    else
        warn "バックアップファイルがありません"
    fi
else
    warn "/config/backup ディレクトリがありません"
fi

if [ -f /config/scripts/backup.sh ]; then
    pass "自動バックアップスクリプトあり"
else
    warn "自動バックアップスクリプトがありません"
fi

echo ""
echo "========================================"
echo " 確認完了"
echo "========================================"

#!/usr/bin/env bash
# PiKVMの状態確認スクリプト

set -euo pipefail

PIKVM_HOST="${PIKVM_HOST:-pikvm.local}"

echo "=== PiKVM状態確認 ==="
echo "ホスト: $PIKVM_HOST"
echo ""

# 接続確認
if ! ping -c 1 "$PIKVM_HOST" >/dev/null 2>&1; then
    echo "❌ PiKVMに到達できません"
    exit 1
fi
echo "✅ ネットワーク接続: OK"

# SSH接続確認
if ! ssh -o ConnectTimeout=5 "root@${PIKVM_HOST}" "exit" 2>/dev/null; then
    echo "❌ SSH接続に失敗しました"
    exit 1
fi
echo "✅ SSH接続: OK"

# システム情報取得
echo ""
echo "--- システム情報 ---"
ssh "root@${PIKVM_HOST}" 'cat /etc/os-release | grep PRETTY_NAME'
ssh "root@${PIKVM_HOST}" 'uptime'

# サービス状態確認
echo ""
echo "--- サービス状態 ---"
ssh "root@${PIKVM_HOST}" 'systemctl is-active kvmd' | sed 's/^/kvmd: /'
ssh "root@${PIKVM_HOST}" 'systemctl is-active kvmd-webterm' | sed 's/^/webterm: /'

# ディスク使用量
echo ""
echo "--- ディスク使用量 ---"
ssh "root@${PIKVM_HOST}" 'df -h / | tail -1'

# 温度情報
echo ""
echo "--- CPU温度 ---"
ssh "root@${PIKVM_HOST}" 'vcgencmd measure_temp' || echo "温度情報取得不可"

echo ""
echo "✅ すべての確認が完了しました"

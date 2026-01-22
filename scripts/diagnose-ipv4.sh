#!/bin/bash
# IPv4診断スクリプト
# Usage: ./diagnose-ipv4.sh

set -euo pipefail

echo "=== IPv4 診断開始 ==="

echo -e "\n[1] インターフェース状態"
ifconfig | grep -E "^[a-z]|inet " | grep -v inet6

echo -e "\n[2] デフォルトゲートウェイ"
netstat -rn | grep default | grep -v ":"

echo -e "\n[3] DNS設定"
scutil --dns | grep "nameserver\[[0-9]*\]" | head -5

echo -e "\n[4] ゲートウェイへのping"
GW=$(netstat -rn | grep "default.*UGSc" | awk '{print $2}' | head -1)
if [ -n "$GW" ]; then
    ping -c 3 -t 2 "$GW" 2>&1 || echo "⚠️ ゲートウェイ応答なし"
else
    echo "❌ ゲートウェイ取得失敗"
fi

echo -e "\n[5] 外部IPv4接続テスト (8.8.8.8)"
ping -c 3 -t 2 8.8.8.8 2>&1 || echo "❌ 外部IPv4接続失敗"

echo -e "\n[6] DNS解決テスト"
dig +short A google.com @8.8.8.8 2>&1 || echo "❌ DNS解決失敗"

echo -e "\n[7] HTTP接続テスト"
curl -4 -s -o /dev/null -w "HTTP: %{http_code}, IP: %{remote_ip}\n" --connect-timeout 5 https://httpbin.org/ip 2>&1 || echo "❌ HTTP接続失敗"

echo -e "\n[8] ルーティングテーブル (IPv4)"
netstat -rn -f inet | head -15

echo -e "\n=== 診断完了 ==="

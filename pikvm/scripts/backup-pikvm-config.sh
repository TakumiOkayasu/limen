#!/usr/bin/env bash
# PiKVM設定ファイルのバックアップスクリプト

set -euo pipefail

PIKVM_HOST="${PIKVM_HOST:-pikvm.local}"
BACKUP_DIR="$(cd "$(dirname "$0")/../config/backup" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== PiKVM設定バックアップ ==="
echo "ホスト: $PIKVM_HOST"
echo "保存先: $BACKUP_DIR"

mkdir -p "$BACKUP_DIR"

# 設定ファイルのバックアップ
echo "設定ファイルをバックアップ中..."
scp "root@${PIKVM_HOST}:/etc/kvmd/override.yaml" "$BACKUP_DIR/override.yaml.$TIMESTAMP" || true
scp "root@${PIKVM_HOST}:/etc/systemd/network/eth0.network" "$BACKUP_DIR/eth0.network.$TIMESTAMP" || true
scp "root@${PIKVM_HOST}:/etc/ssh/sshd_config" "$BACKUP_DIR/sshd_config.$TIMESTAMP" || true

# 最新のシンボリックリンクを更新
ln -sf "override.yaml.$TIMESTAMP" "$BACKUP_DIR/override.yaml.latest"
ln -sf "eth0.network.$TIMESTAMP" "$BACKUP_DIR/eth0.network.latest"
ln -sf "sshd_config.$TIMESTAMP" "$BACKUP_DIR/sshd_config.latest"

echo "✅ バックアップ完了"
echo "保存先: $BACKUP_DIR"

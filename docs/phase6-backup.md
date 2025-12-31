# Phase 6: バックアップ体制

## タスク6-1: VyOS設定バックアップ

**目的**: 設定の外部保存とロールバック対応

### 手動バックアップ

```bash
# 日付付きでバックアップ
save /config/backup/config-$(date +%Y%m%d-%H%M%S).boot

# バックアップ一覧
ls /config/backup/

# 特定のバックアップから復元
load /config/backup/config-YYYYMMDD-HHMMSS.boot
commit
save
```

### 自動バックアップ（cronで設定）

```bash
# ディレクトリ作成（初回のみ）
sudo mkdir -p /config/backup
sudo mkdir -p /config/scripts
```

```
configure

# 毎日3:00にバックアップ
set system task-scheduler task daily-backup crontab-spec '0 3 * * *'
set system task-scheduler task daily-backup executable path '/config/scripts/backup.sh'

commit
save
```

### バックアップスクリプト作成

ファイル: `/config/scripts/backup.sh`

```bash
#!/bin/bash
BACKUP_DIR="/config/backup"
DATE=$(date +%Y%m%d)
MAX_BACKUPS=30

# バックアップ実行
cp /config/config.boot "${BACKUP_DIR}/config-${DATE}.boot"

# 古いバックアップを削除（30日以上前）
find "${BACKUP_DIR}" -name "config-*.boot" -mtime +${MAX_BACKUPS} -delete
```

```bash
# スクリプトに実行権限付与
chmod +x /config/scripts/backup.sh
```

### 外部バックアップ（推奨）

```bash
# SCPで外部サーバーに転送
scp /config/config.boot user@backup-server:/backups/vyos/
```

---

## タスク6-2: WireGuard鍵のバックアップ

**目的**: 鍵の紛失防止とローテーション対応

### 鍵の保存場所確認

```bash
# VyOS上の鍵ファイル
ls -la /config/auth/wireguard/
```

### バックアップ手順

```bash
# 鍵ディレクトリごとバックアップ
tar -czf /config/backup/wireguard-keys-$(date +%Y%m%d).tar.gz /config/auth/wireguard/

# 外部に安全に転送（暗号化推奨）
scp /config/backup/wireguard-keys-*.tar.gz user@backup-server:/backups/vyos/
```

### ⚠️ セキュリティ注意

- 秘密鍵は絶対に平文でメール送信しない
- バックアップ先も暗号化ストレージを使用
- アクセス権限を最小限に

### 鍵ローテーション手順（必要時）

```
# 新しい鍵ペアを生成
generate wireguard named-keypairs rotation-$(date +%Y%m%d)

# 新しい鍵に切り替え
configure
set interfaces wireguard wg0 private-key rotation-$(date +%Y%m%d)
commit
save

# 全クライアントに新しい公開鍵を配布
show wireguard keypairs pubkey rotation-$(date +%Y%m%d)
```

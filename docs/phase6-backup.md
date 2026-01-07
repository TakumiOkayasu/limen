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

**方法1: SCPで外部サーバーに転送**
```bash
scp /config/config.boot user@backup-server:/backups/vyos/
```

**方法2: Mac側からpullする**
```bash
# Mac側で実行
scp vyos:/config/config.boot ~/backups/vyos/config-$(date +%Y%m%d).boot
```

**方法3: Gitリポジトリで管理**
```bash
# Mac側でバックアップをGit管理
cd ~/backups/vyos
scp vyos:/config/config.boot ./config.boot
git add config.boot
git commit -m "backup: $(date +%Y-%m-%d)"
```

**完了条件**:
- [ ] `/config/backup/`にバックアップファイルが存在する
- [ ] task-schedulerで自動バックアップが設定されている
- [ ] 外部(Mac等)にもバックアップがコピーされている

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

**完了条件**:
- [ ] WireGuard鍵がバックアップされている
- [ ] バックアップファイルのパーミッションが適切(600)

---

## 災害復旧手順

VyOSが起動しなくなった場合の復旧手順:

### 1. 新規インストール
1. VyOS ISOをUSBに書き込み
   ```bash
   # [Mac]
   diskutil list  # USBデバイス確認
   diskutil unmountDisk /dev/diskX
   sudo dd if=vyos-*.iso of=/dev/rdiskX bs=1m status=progress
   ```
2. USBからブート (BIOS/UEFIでブート順変更)
3. `install image`でクリーンインストール
4. 再起動

### 2. 最小限の設定 (SSH接続可能にする)
```bash
# VyOSコンソールで実行
configure

# LAN側IPとSSH設定
set interfaces ethernet eth2 address '192.168.1.1/24'
set interfaces ethernet eth2 description 'LAN'
set service ssh listen-address '192.168.1.1'
set service ssh port '22'

commit
save
```

### 3. SSH経由で設定復元
```bash
# [Mac] バックアップファイルをVyOSに転送
scp ~/backups/vyos/config-YYYYMMDD.boot vyos@192.168.1.1:/tmp/

# または scripts/backup-vyos-config.txt を使用
scp scripts/backup-vyos-config.txt vyos@192.168.1.1:/tmp/
```

```bash
# [VyOS] 設定を復元
configure
load /tmp/config-YYYYMMDD.boot
commit
save
```

### 4. WireGuard鍵復元 (設定済みの場合)
```bash
# 鍵ファイルを転送
scp wireguard-keys.tar.gz vyos@192.168.1.1:/tmp/

# VyOS上で展開
sudo tar -xzf /tmp/wireguard-keys.tar.gz -C /
```

### 5. 動作確認
- [ ] SSHログイン可能
- [ ] IPv6通信可能 (`ping6 google.com`)
- [ ] WireGuard接続可能 (設定済みの場合)

---

## カーネル更新手順 (危険な操作)

⚠️ **警告**: カーネル更新は失敗するとVyOSが起動不能になります。
必ず以下の手順に従ってください。

### 事前準備チェックリスト

- [ ] 現在の設定をバックアップした (`show configuration commands > /config/backup-YYYYMMDD.txt`)
- [ ] 現在のカーネルバージョンを記録した (`uname -r`)
- [ ] **ビルドしたdebのconfigを検証した** (後述)
- [ ] テスト環境(VM)で動作確認した
- [ ] 物理コンソールアクセスを確保した
- [ ] GRUBで旧カーネル起動できることを確認した
- [ ] ロールバック手順を把握している
- [ ] メンテナンス時間を確保した (最低1時間)

### ビルド成果物の検証 (必須)

**インストール前に必ず実行**:

```bash
# [VyOS] debパッケージの内容を検証
mkdir -p /tmp/kernel-check
dpkg -x /path/to/linux-image-*.deb /tmp/kernel-check
grep CONFIG_MODULE_SIG_FORCE /tmp/kernel-check/boot/config-*

# 期待する出力: # CONFIG_MODULE_SIG_FORCE is not set
# 以下が出たら絶対にインストールしない:
#   CONFIG_MODULE_SIG_FORCE=y
```

### インストール手順

```bash
# 1. 設定バックアップ (再確認)
show configuration commands > /config/backup-$(date +%Y%m%d-%H%M).txt

# 2. カーネルインストール
sudo dpkg -i linux-image-*.deb

# 3. インストール後、再起動前に確認
ls /boot/vmlinuz-*
# 複数のカーネルがあることを確認

# 4. 再起動
sudo reboot
```

### ロールバック手順

起動に失敗した場合:

1. 起動直後に **Shift** または **Esc** を連打してGRUBメニュー表示
2. GRUBコマンドラインに入った場合は `normal` でメニュー表示
3. 旧カーネルを選択して起動
4. 起動後、問題のカーネルを削除:
   ```bash
   sudo dpkg --force-depends --purge linux-image-<問題のバージョン>
   ```

### 失敗事例 (2026-01-07)

詳細: [failure-log-2026-01-07-kernel-update.md](failure-log-2026-01-07-kernel-update.md)

- MODULE_SIG_FORCE=n でビルドしたつもりが反映されていなかった
- 検証なしでインストールした結果、VyOS起動不能に
- 復旧にVyOS再インストールが必要になった

# 災害復旧ガイド

VyOSが起動しなくなった場合、または設定が破損した場合の復旧手順。

## 復旧方法の選択

| 方法 | 用途 | 所要時間 |
|------|------|----------|
| **A. loadコマンド** | VyOSは起動するが設定がおかしい | 5分 |
| **B. 一括復元スクリプト** | クリーンインストール後の完全復旧 | 15分 |
| **C. 手動復元** | スクリプトが動かない場合 | 30分 |

---

## 方法A: loadコマンドで設定復元

VyOSが起動し、設定ファイルのバックアップがある場合の最速復旧方法。

### 前提条件

- VyOSが起動している
- `/config/backup/` または外部に設定バックアップがある

### 手順

```bash
# 1. バックアップファイルを確認
ls /config/backup/

# 2. 設定モードに入る
configure

# 3. バックアップから設定を読み込む
load /config/backup/config-YYYYMMDD.boot

# 4. 差分を確認 (任意)
compare

# 5. 適用・保存
commit
save
```

### 外部からバックアップを転送する場合

```bash
# [Mac] バックアップをVyOSに転送
scp ~/backups/vyos/config-YYYYMMDD.boot vyos@192.168.1.1:/tmp/

# [VyOS] 読み込み
configure
load /tmp/config-YYYYMMDD.boot
commit
save
```

---

## 方法B: 一括復元スクリプト

クリーンインストール後の完全復旧。シークレット値を `.env` で管理し、vbashスクリプトで一括設定。

### 必要なファイル

| ファイル | 場所 | 用途 |
|----------|------|------|
| `vyos-restore.env.example` | `scripts/` | 環境変数テンプレート |
| `generate-vyos-restore.sh` | `scripts/` | スクリプト生成ツール |

### 必要なシークレット値

| 項目 | 取得方法 | 備考 |
|------|----------|------|
| SSH公開鍵 | `cat ~/.ssh/id_ed25519-touch-id.pub` | 既存 |
| WireGuard Mac公開鍵 | `cat ~/.wireguard/mac-public.key` | 既存 |
| WireGuard iPhone公開鍵 | `cat ~/.wireguard/iphone-public.key` | 既存 |
| WireGuard サーバー秘密鍵 | VyOSで生成 | **再生成** |
| Cloudflare API Token | Cloudflareで生成 | **再生成** |

### 手順

#### Step 1: カスタムISOでVyOSをインストール

```bash
# [Mac] USBにISOを書き込み
diskutil list                    # USBデバイス確認 (例: /dev/disk4)
diskutil unmountDisk /dev/disk4
sudo dd if=vyos-custom-*.iso of=/dev/rdisk4 bs=1m status=progress
```

USBからブート → `install image` → 再起動

#### Step 2: 最小限の設定 (コンソール)

```bash
configure

set interfaces ethernet eth2 address '192.168.1.1/24'
set interfaces ethernet eth2 description 'LAN'
set service ssh listen-address '192.168.1.1'
set service ssh port '22'

commit
save
exit
```

#### Step 3: SSH接続テスト

```bash
# [Mac] 古いホスト鍵を削除 (再インストール後は必須)
ssh-keygen -R 192.168.1.1

# 接続テスト
ssh vyos@192.168.1.1
```

#### Step 4: WireGuard サーバー鍵を生成

```bash
# [VyOS] 鍵ペア生成
run generate pki wireguard key-pair
```

出力例:
```
Private key: aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890abcde=
Public key: XyZ1234567890abcdefghijklmnopqrstuvwxyzABC=
```

**秘密鍵** (`Private key`) をメモ。

#### Step 5: Cloudflare API Token を生成

1. [Cloudflareダッシュボード](https://dash.cloudflare.com/) にログイン
2. My Profile → API Tokens → Create Token
3. テンプレート: 「ゾーン DNS を編集する」
4. 対象ゾーン: `murata-lab.net` に限定
5. Create Token → トークンをコピー

#### Step 6: .env を設定

```bash
# [Mac]
cd ~/prog/murata-lab/limen/scripts
cp vyos-restore.env.example vyos-restore.env
vim vyos-restore.env
```

設定する値:
```bash
WIREGUARD_SERVER_PRIVKEY="aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890abcde="
CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
```

#### Step 7: スクリプト生成

```bash
./generate-vyos-restore.sh
```

出力: `vyos-restore.vbash`

#### Step 8: VyOSに転送・実行

```bash
# [Mac]
scp vyos-restore.vbash vyos@192.168.1.1:/tmp/

# [VyOS]
vbash /tmp/vyos-restore.vbash
```

#### Step 9: バックアップスクリプト作成

```bash
# [VyOS]
sudo mkdir -p /config/backup /config/scripts

cat << 'SCRIPT' | sudo tee /config/scripts/backup.sh
#!/bin/bash
BACKUP_DIR="/config/backup"
DATE=$(date +%Y%m%d)
MAX_BACKUPS=30
cp /config/config.boot "${BACKUP_DIR}/config-${DATE}.boot"
find "${BACKUP_DIR}" -name "config-*.boot" -mtime +${MAX_BACKUPS} -delete
SCRIPT

sudo chmod +x /config/scripts/backup.sh
```

#### Step 10: クライアント設定更新

Mac/iPhoneのWireGuard設定で `PublicKey` を新しいVyOS公開鍵に更新。

`~/.wireguard/mac.conf`:
```ini
[Peer]
PublicKey = <新しいVyOS公開鍵>   # ← ここを更新
Endpoint = router.murata-lab.net:51820
AllowedIPs = 10.10.10.1/32, fd00:10:10:10::1/128
PersistentKeepalive = 25
```

#### Step 11: 動作確認

```bash
# [VyOS]
ping6 2001:4860:4860::8888    # IPv6疎通
ping 8.8.8.8                   # IPv4疎通 (WXR経由)
show interfaces                # インターフェース確認
show interfaces wireguard      # WireGuard確認
show dns dynamic status        # DDNS確認
```

---

## 方法C: 手動復元

スクリプトが動かない場合、`scripts/recovery-vyos-config.sh` を参照して手動で設定。

```bash
# [Mac] 手順を表示
./scripts/recovery-vyos-config.sh | less
```

各STEPをVyOSのconfigureモードでコピペして実行。

---

## トラブルシューティング

### SSH接続できない

```bash
# [Mac] 古いホスト鍵を削除
ssh-keygen -R 192.168.1.1

# パスワード認証で接続 (初期状態)
ssh vyos@192.168.1.1
# デフォルトパスワード: vyos
```

### DHCPv6-PDが取得できない

DUID-LL形式が必須。詳細は [troubleshooting-dhcpv6-pd.md](troubleshooting-dhcpv6-pd.md) 参照。

```bash
# DUIDファイルを確認
od -A x -t x1z /var/lib/dhcpv6/dhcp6c_duid
# 期待: 0a 00 00 03 00 01 c4 62 37 08 0e 53
```

### WireGuard接続できない

1. VyOS側でインターフェース確認: `show interfaces wireguard`
2. ファイアウォールログ確認: `show log | grep -i wire`
3. クライアントの `PublicKey` が新しいVyOS公開鍵になっているか確認

### IPv4が通らない

1. WXRが起動しているか確認
2. eth0のリンク確認: `show interfaces ethernet eth0`
3. WXRへのping: `ping 192.168.100.1`
4. NATルール確認: `show nat source rules`

---

## 関連ファイル

| ファイル | 用途 |
|----------|------|
| `scripts/vyos-restore.env.example` | シークレット値テンプレート |
| `scripts/generate-vyos-restore.sh` | vbashスクリプト生成ツール |
| `scripts/recovery-vyos-config.sh` | 手動復元用の手順表示 |
| `scripts/backup-vyos-config.txt` | 設定コマンド一覧 (参照用) |

---

## 定期バックアップの確認

```bash
# [VyOS] バックアップ一覧
ls -la /config/backup/

# task-scheduler確認
show configuration commands | grep task-scheduler
```

バックアップは毎日3:00に自動実行される。

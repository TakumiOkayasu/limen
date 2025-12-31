# Phase 0: VyOSインストール・基本設定

## タスク0-1: VyOSインストール

**目的**: VyOS Rolling Releaseを実機にインストール

**手順**:
1. https://vyos.net/get/nightly-builds/ からISOダウンロード
2. USBメモリに書き込み(Rufus等)
3. USBから起動、`install image`コマンドでインストール
4. 再起動

**完了条件**: VyOSが起動し、コンソールからログイン可能

---

## タスク0-2: タイムゾーン・NTP設定

**目的**: ログのタイムスタンプを日本時間にする、時刻同期

**VyOSコマンド**:
```
configure

set system time-zone Asia/Tokyo
set service ntp server ntp.nict.jp
set service ntp server time.cloudflare.com

commit
save
```

**確認コマンド**:
```bash
show date
show ntp
```

**完了条件**:
- [ ] `show date`でJSTが表示される
- [ ] `show ntp`でサーバーと同期している

---

## タスク0-3: 管理者パスワード変更

**目的**: デフォルトパスワードからの変更

**VyOSコマンド**:
```
configure

set system login user vyos authentication plaintext-password <新しいパスワード>

commit
save
```

**パスワードポリシー（推奨）**:
- 16文字以上
- 英大文字・小文字・数字・記号を含む
- パスワードマネージャーで生成・管理

**完了条件**: 新しいパスワードでログイン可能

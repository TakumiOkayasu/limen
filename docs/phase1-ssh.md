# Phase 1: LAN側SSH有効化

## タスク1-1: SSH有効化（LAN側のみ）

**目的**: リモートから設定作業できるようにする

**VyOSコマンド**:
```
configure

set service ssh port 22
set service ssh listen-address <LAN側IPアドレス>

commit
save
```

**完了条件**: LAN側PCから`ssh vyos@<IP>`で接続可能

---

## タスク1-2: SSH公開鍵登録（TouchID連携）

**目的**: パスワード入力なしでSSH接続

### 1-2-1. 既存のTouchID連携鍵を使用

既に `~/.ssh/id_ed25519-touch-id` が存在する場合はそれを使用。

```bash
# 公開鍵を確認
cat ~/.ssh/id_ed25519-touch-id.pub
```

**新規作成が必要な場合のみ**:
```bash
# TouchID連携のed25519鍵を生成
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519-touch-id

# Keychainに登録
ssh-add --apple-use-keychain ~/.ssh/id_ed25519-touch-id
```

### 1-2-2. Mac側SSH設定（~/.ssh/config）

```
Host vyos
    HostName <LAN側IPアドレス>
    User vyos
    IdentityFile ~/.ssh/id_ed25519-touch-id
    UseKeychain yes
    AddKeysToAgent yes

Host vyos-vpn
    HostName 10.10.10.1
    User vyos
    IdentityFile ~/.ssh/id_ed25519-touch-id
    UseKeychain yes
    AddKeysToAgent yes
```

### 1-2-3. VyOS側に公開鍵を登録

```bash
# まず公開鍵の内容をコピー
cat ~/.ssh/id_ed25519-touch-id.pub
# 出力例: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... user@host
```

```
configure

# 公開鍵を登録（keyには"ssh-ed25519 "以降の文字列を指定）
set system login user vyos authentication public-keys macbook type ssh-ed25519
set system login user vyos authentication public-keys macbook key <AAAAC3NzaC1lZDI1NTE5...の部分>

commit
save
```

### 1-2-4. 接続テスト（パスワード認証無効化の前に必ず実行）

```bash
# 新しいターミナルで接続テスト
ssh vyos
```

**接続成功を確認してから**パスワード認証を無効化:
```
configure

set service ssh disable-password-authentication

commit
save
```

**完了条件**:
- [ ] TouchIDまたはMacログインパスワードでSSH接続可能
- [ ] パスフレーズ入力不要

**⚠️ 注意**: パスワード認証を無効化する前に、必ず公開鍵認証でログインできることを確認すること。失敗するとコンソール経由でしかログインできなくなる。

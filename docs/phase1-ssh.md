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

### 1-2-1. Mac側でSSH鍵生成

```bash
# 鍵生成（強力なパスフレーズを設定）
ssh-keygen -t ed25519 -C "vyos-router" -f ~/.ssh/vyos_ed25519

# Keychainに登録（パスフレーズ入力は初回のみ）
ssh-add --apple-use-keychain ~/.ssh/vyos_ed25519

# 公開鍵を表示（VyOSに登録する）
cat ~/.ssh/vyos_ed25519.pub
```

### 1-2-2. Mac側SSH設定（~/.ssh/config）

```
Host vyos
    HostName 10.10.10.1
    User vyos
    IdentityFile ~/.ssh/vyos_ed25519
    UseKeychain yes
    AddKeysToAgent yes

Host vyos-vpn
    HostName 10.10.10.1
    User vyos
    IdentityFile ~/.ssh/vyos_ed25519
    UseKeychain yes
    AddKeysToAgent yes
    ProxyCommand none
```

### 1-2-3. VyOS側に公開鍵を登録

```
configure

set system login user vyos authentication public-keys macbook type ssh-ed25519
set system login user vyos authentication public-keys macbook key <公開鍵の中身(ssh-ed25519 AAAA...の部分)>

# パスワード認証を無効化(公開鍵登録後に実行)
set service ssh disable-password-authentication

commit
save
```

### 1-2-4. 接続テスト

```bash
ssh vyos
```

**完了条件**:
- [ ] TouchIDまたはMacログインパスワードでSSH接続可能
- [ ] パスフレーズ入力不要

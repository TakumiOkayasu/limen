# Phase 5: 運用設定

## タスク5-1: Cloudflare DDNS設定

**目的**: IPv6アドレス変更時に自動でDNSレコードを更新

### 事前準備

1. Cloudflareダッシュボードでドメインを管理
2. APIトークンを作成（Zone:DNS:Edit権限）
   - My Profile → API Tokens → Create Token
   - "Edit zone DNS"テンプレートを使用
3. 更新対象のホスト名を決定（例: `router.example.com`）

### VyOSコマンド

```
configure

set service dns dynamic name cloudflare address interface eth0
set service dns dynamic name cloudflare protocol cloudflare
set service dns dynamic name cloudflare zone <your-domain.com>
set service dns dynamic name cloudflare host-name <router.your-domain.com>
set service dns dynamic name cloudflare username <Cloudflareメールアドレス>
set service dns dynamic name cloudflare password <CloudflareAPIトークン>
set service dns dynamic name cloudflare ip-version ipv6

commit
save
```

### 確認コマンド

```
show dns dynamic status
```

### WireGuardクライアント設定の更新

```ini
[Peer]
Endpoint = router.your-domain.com:51820
```

**完了条件**:
- [ ] `show dns dynamic status`でIPv6アドレスが表示される
- [ ] DNSレコードが自動更新される

---

## タスク5-2: ファイアウォールログ設定

**目的**: 攻撃検知とトラブルシューティングのためのログ収集

### VyOSコマンド

```
configure

# デフォルトdropのログを有効化
set firewall ipv6 name WAN6_IN default-log
set firewall ipv4 name VPN_TO_LAN default-log
set firewall ipv4 name VPN_TO_WAN default-log
set firewall ipv6 name VPN6_TO_LAN default-log
set firewall ipv6 name VPN6_TO_WAN default-log

# rate limitでdropされたパケットのログ
set firewall ipv6 name WAN6_IN rule 25 log

commit
save
```

### ログ確認コマンド

```bash
# リアルタイムログ監視
monitor log | grep -i drop

# 最近のドロップログ
show log | grep -i '\[WAN6_IN-'

# ファイアウォール統計
show firewall statistics
```

### ログローテーション

VyOS標準で自動:
- `/var/log/messages`に記録
- logrotateで自動ローテーション

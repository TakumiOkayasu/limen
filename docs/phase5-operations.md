# Phase 5: 運用設定

## タスク5-1: Cloudflare DDNS設定

**目的**: IPv6アドレス変更時に自動でDNSレコードを更新

### 事前準備

1. Cloudflareダッシュボードでドメインを管理
2. APIトークンを作成（Zone:DNS:Edit権限）
   - My Profile → API Tokens → Create Token
   - "Edit zone DNS"テンプレートを使用
   - 対象ゾーンを限定するとより安全
3. 更新対象のホスト名を決定（例: `router.example.com`）
4. **事前にCloudflareでAAAAレコードを作成しておく**（初期値は適当でOK）

### VyOSコマンド

```
configure

set service dns dynamic name cloudflare address interface eth0
set service dns dynamic name cloudflare protocol cloudflare
set service dns dynamic name cloudflare zone <your-domain.com>
set service dns dynamic name cloudflare host-name <router.your-domain.com>
set service dns dynamic name cloudflare password <CloudflareAPIトークン>
set service dns dynamic name cloudflare ip-version ipv6

commit
save
```

**注意**:
- `username`は不要（APIトークン認証の場合）
- `password`にはAPIトークンを設定
- `ip-version ipv6`でIPv6のみ更新(AAAAレコード)

### 確認コマンド

```bash
# DDNS状態確認
show dns dynamic status

# 手動で更新を実行
restart dns dynamic

# DNSレコード確認(外部から)
dig AAAA router.your-domain.com
```

### WireGuardクライアント設定の更新

DDNSホスト名をEndpointに使用:
```ini
[Peer]
Endpoint = router.your-domain.com:51820
```

### トラブルシューティング

```bash
# ddclientのログ確認
show log | grep -i ddclient

# 設定確認
show configuration commands | grep dynamic
```

| 症状 | 原因 | 対処 |
|------|------|------|
| 更新されない | APIトークン権限不足 | Zone:DNS:Edit権限を確認 |
| エラー | AAAAレコード未作成 | Cloudflareで事前作成 |
| タイムアウト | eth0にIPv6なし | `show interfaces`で確認 |

**完了条件**:
- [ ] `show dns dynamic status`でIPv6アドレスが表示される
- [ ] `dig AAAA`でDNSレコードが正しいIPv6を返す

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

**完了条件**:
- [ ] `show firewall statistics`で統計が表示される
- [ ] dropログが`/var/log/messages`に記録される

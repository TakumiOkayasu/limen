# Phase 5: 運用設定

**完了日**: 2026-01-13

## タスク5-1: Cloudflare DDNS設定

**目的**: IPv6アドレス変更時に自動でDNSレコードを更新

### 事前準備

1. Cloudflareダッシュボードでドメインを管理
2. APIトークンを作成 (Zone:DNS:Edit権限)
   - My Profile → API Tokens → Create Token
   - "ゾーン DNS を編集する"テンプレートを使用
   - 対象ゾーンを限定するとより安全
3. 更新対象のホスト名を決定 (例: `router.murata-lab.net`)
4. **事前にCloudflareでAAAAレコードを作成しておく** (初期値は適当でOK)
5. **プロキシステータス: DNSのみ** (プロキシ済みにしない)

### VyOSコマンド

```bash
configure

set service dns dynamic name cloudflare address interface eth1
set service dns dynamic name cloudflare protocol cloudflare
set service dns dynamic name cloudflare zone murata-lab.net
set service dns dynamic name cloudflare host-name router.murata-lab.net
set service dns dynamic name cloudflare password '<CloudflareAPIトークン>'
set service dns dynamic name cloudflare ip-version ipv6

commit
save
```

**注意**:
- `address interface eth1` (WAN側、IPv6を持つインターフェース)
- `username`は不要 (APIトークン認証の場合)
- `password`にはAPIトークンを設定
- `ip-version ipv6`でIPv6のみ更新 (AAAAレコード)

### 確認コマンド

```bash
# DDNS状態確認
show dns dynamic status

# 手動で更新を実行
restart dns dynamic

# ログ確認
show log | grep -i ddclient

# DNSレコード確認 (外部から)
dig AAAA router.murata-lab.net +short
```

### トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| 更新されない | APIトークン権限不足 | Zone:DNS:Edit権限を確認 |
| エラー | AAAAレコード未作成 | Cloudflareで事前作成 |
| IPが取得できない | ip-version未設定 | `set ... ip-version ipv6` を追加 |
| noconnect表示 | 表示上の問題 | ログでSUCCESSを確認すれば問題なし |

**完了条件**:
- [x] `show dns dynamic status`でIPv6アドレスが表示される
- [x] `dig AAAA`でDNSレコードが正しいIPv6を返す

---

## タスク5-2: ファイアウォールログ設定

**目的**: 攻撃検知とトラブルシューティングのためのログ収集

### VyOSコマンド (新構文)

```bash
configure

# デフォルトdropのログを有効化
set firewall ipv6 forward filter default-log
set firewall ipv6 input filter default-log

commit
save
```

**注意**: VyOS 2026.xでは `firewall ipv6 name WAN6_IN` (旧構文) ではなく `firewall ipv6 forward filter` / `firewall ipv6 input filter` (新構文) を使用

### ログ確認コマンド

```bash
# ファイアウォール統計
show firewall

# リアルタイムログ監視
monitor log | grep -i drop

# 最近のログ
show log | tail -50
```

### ログローテーション

VyOS標準で自動:
- `/var/log/messages`に記録
- logrotateで自動ローテーション

**完了条件**:
- [x] `show firewall`で統計が表示される
- [x] dropログが`/var/log/messages`に記録される

---

## 現在の設定値

| 項目 | 値 |
|------|-----|
| DDNSドメイン | router.murata-lab.net |
| DDNSインターフェース | eth1 |
| DDNSプロトコル | cloudflare |
| ログ対象 | forward filter, input filter |

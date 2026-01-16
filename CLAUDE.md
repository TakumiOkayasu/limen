# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

# ⚠️ 最重要: セッション開始時の必須アクション

**Claude Code 起動直後、作業開始前に必ず以下を実行すること:**

1. **この CLAUDE.md を最後まで読む**
2. **`secrets/docs/` ディレクトリ内のドキュメントを確認する**
   - 特に `secrets/docs/reference.md` (機器情報、MACアドレス一覧、環境情報)
   - **`secrets/docs/hardware-specs.md`** (使用機材の詳細スペック、ポート数、対応速度)
   - 関連する phase ドキュメント
   - トラブルシューティング履歴
3. **過去の失敗パターンを確認する** (`secrets/docs/troubleshooting-*.md`, `secrets/docs/failure-log-*.md`)
4. **使用機材について質問する前に `secrets/docs/hardware-specs.md` を確認する**
   - WebSearchやユーザーに確認する前に**必ず**このファイルを読む
   - MACアドレス、ポート数、対応速度、物理接続図が記載されている

**なぜ重要か**: このプロジェクトは複雑なネットワーク構成を扱う。MACアドレスの取り違え、機器の役割の誤解など、ドキュメントを読めば防げるミスで何時間も無駄にした実績がある。**推測で作業するな。ドキュメントを読め。**

---

# BIGLOBE + MAP-E + 10Gbps 自作ルーター構築プロジェクト

## プロジェクト概要

BIGLOBE光(10Gbps)環境で、MAP-Eの制約を回避しつつ10Gbpsを最大限活用する自作ルーターを構築する。

### 設計思想

- **IPv6を主役**: 10Gbps活用可能、WXRを一切通さない
- **IPv4は例外扱い**: ポリシールーティングでWXRへ転送
- **MAP-Eは保険**: 捨てず、重要視もしない

### 物理構成

```
[ONU] ── [LXW-10G5] ─┬─ 10G ── [自作ルーター] ── [LAN]
                     │           (eth1)         (eth2)
                     │                │
                     │           (別セグメント 1G)
                     │              (eth0)
                     │                │
                     └─ 10G ── [WXR9300BE6P]
                               (MAP-E専用)
```

- **LXW-10G5**: BUFFALO 10GbE L2スイッチ (5ポート)

### NIC構成

| VyOS名 | NIC | 速度 | 用途 |
|--------|-----|------|------|
| eth0 | オンボード | 1GbE | WXR WAN側接続 (MAP-E upstream) |
| eth1 | Intel X540-T2 Port2 | 10GbE | WAN (LXW-10G5経由でONU) |
| eth2 | Intel X540-T2 Port1 | 10GbE | LAN (主要機器向け) |
| (未使用) | RTL8126 | 5GbE | **将来eth0の代替予定** (WXR接続を5Gbpsに高速化) |

### WXR接続用別セグメント (192.168.100.x)

自作ルーターとWXR9300BE6Pを1GbEオンボードNICで直結し、IPv4転送専用の別セグメントを構築する。

- 自作ルーター側: 192.168.100.2/24
- WXR側 (LAN): 192.168.100.1/24 (DHCPサーバー無効)
- 用途: IPv4トラフィックをWXR経由でMAP-Eに転送
- 帯域: 1Gbps上限 (IPv4は例外扱いなので問題なし)

### 役割分担

| 装置 | 役割 |
|------|------|
| 自作ルーター | IPv6ルーター, RA/DHCPv6-PD取得, FW, ポリシールーティング, LANのデフォルトGW |
| WXR9300BE6P | MAP-E CE専用, IPv4 NAT, (必要なら)無線AP |

### トラフィックフロー

- **IPv6**: LAN → 自作ルーター → LXW-10G5 → ONU → NGN (10Gbps狙い)
- **IPv4**: LAN → 自作ルーター → WXR → MAP-Eトンネル (1Gbps上限)

---

## コマンド指示のルール

**重要**: コマンドを指示する際は、必ず実行先を明示すること。

- **[Mac]** - Macのターミナルで実行
- **[VyOS]** - VyOSのコンソール/SSHで実行
- **[WXR]** - WXR管理画面で操作

例:
```
[VyOS] show interfaces
[Mac] ping 192.168.1.1
```

---

## ユーザーフレンドリーなコミュニケーション

**重要**: 作業開始前・作業中に環境状態を明示すること。

### 環境状態の表示

作業を指示する前に、関連する全ての機器の状態を確認・表示する:

```
【現在の環境状態】
- VyOS: [状態] (例: SSH接続中、設定モード等)
- WXR: [モード] (ルーターモード/APモード)
- 物理接続: [確認事項]
- 関連サービス: [状態]
```

### 必須確認事項

- **モード変更が必要な場合は事前に伝える**
- **前提条件を明示する** (例: 「WXRがルーターモードである必要があります」)
- **現在の状態と目標状態の差分を説明する**

---

## Git操作ルール

**重要**: ブランチ作成と移動はAI (Claude Code) の仕事。

- **mainブランチで直接作業しない** - 必ず作業用ブランチを作成
- **ブランチ作成はAIが実行する** - ユーザーに指示を出すのではなく、AIが `git checkout -b` を実行
- **コミット/プッシュはユーザーが実行** - AIはコマンドを提示するのみ
- **マージ後の後片付けもAIの仕事** - `git checkout main && git pull && git branch -d <branch>`
- **DependabotのPRは変更しない** - Dependabotが作成したPRの内容には手を加えない。マージ/クローズの判断のみユーザーが行う

---

## Lintルール

**重要**: Lintの警告は全て修正すること。「既存の警告」も例外ではない。

### pre-commit (Docker)

コミット前に自動でLintが実行される。手動実行も可能:

```bash
# pre-commit hookをインストール
ln -sf ../../scripts/pre-commit .git/hooks/pre-commit

# 手動実行
./scripts/pre-commit
```

pre-commitはDocker内でPythonのpre-commitフレームワークを使用し、以下をチェック:
- **actionlint** - GitHub Actions workflow
- **shellcheck** - シェルスクリプト

### Lintルール

- **警告は全て修正** - 「info」レベルも含む
- **既存コードの警告も修正** - 触ったファイルの警告は全て直す

---

## CI/ビルドスクリプトのルール

### Docker内での権限

- **権限が怪しい箇所は全てsudoをつける** - CI環境では安全性より確実性を優先
- ホストにマウントされたディレクトリへの書き込みは特に注意

### バージョン指定

- **VyOS**: rolling (currentブランチ) を使用。LTSは有料のため使用しない
- **Python**: `python:3-slim` のように常に最新版を使用（固定バージョン指定しない）
- **pip**: 使用前に `pip install --upgrade pip` を実行

### 修正時の説明責任

修正を提案する際は以下を明示すること:

1. **この修正で直ること** - 確実に解決する問題
2. **この修正で直らない可能性があること** - 残存リスク
3. **確認できていないこと** - CI実行時にしか検証できない事項

「絶対大丈夫」とは言わない。不確実性を正直に伝える。

### CI失敗時の調査

**CIの失敗を調査する際は `gh` コマンドを使用する**:

```bash
# 最近のCI実行一覧
gh run list --limit 10

# 失敗したログを取得
gh run view <run_id> --log-failed

# 特定のエラーを検索
gh run view <run_id> --log | grep -E "error|failed|ERROR"

# 成功したCIと比較する場合
gh run list --status success --limit 5
gh run view <成功したrun_id> --log | grep <検索キーワード>
```

---

## 実装順序チェックリスト

### Phase 0: VyOSインストール・基本設定
→ [secrets/docs/phase0-install.md](secrets/docs/phase0-install.md)

- [x] 0-1: VyOSインストール (2025-12-31完了)
- [x] 0-2: タイムゾーン・NTP設定 (Asia/Tokyo, ntp.nict.jp等)
- [x] 0-3: 管理者パスワード変更

### Phase 1: LAN側SSH有効化
→ [secrets/docs/phase1-ssh.md](secrets/docs/phase1-ssh.md)

- [x] 1-1: SSH有効化（LAN側 192.168.1.1 のみ）
- [x] 1-2: SSH公開鍵登録（ed25519, パスワード認証無効）

### Phase 2: IPv6基盤構築
→ [secrets/docs/phase2-ipv6.md](secrets/docs/phase2-ipv6.md)

- [x] 2-1: RA受信・DHCPv6-PD取得 (2404:7a82:4d02:4100::/56)
  - DUID-LL形式必須: `00:03:00:01:MAC`
  - 詳細は [troubleshooting-dhcpv6-pd.md](secrets/docs/troubleshooting-dhcpv6-pd.md)
- [x] 2-2: LAN側RA配布設定 (2026-01-06完了)
  - eth2で ::/64 配布
  - DNS: Cloudflare + Google
- [x] 2-3: IPv6ファイアウォール設定 (2026-01-06完了)
  - input/forward filter設定済み
  - ICMPv6, DHCPv6許可

### Phase 3: WireGuard VPN
→ [secrets/docs/phase3-wireguard.md](secrets/docs/phase3-wireguard.md)

- [x] 3-1: WireGuard鍵生成・インターフェース作成 (2026-01-13完了)
  - wg0: 10.10.10.1/24, fd00:10:10:10::1/64
  - ポート: 51820
- [x] 3-2: WireGuardファイアウォール許可 (2026-01-13完了)
  - input filter rule 40: rate limit (10/min)
  - input filter rule 50: UDP 51820許可
- [x] 3-3: VPNアクセス制限 (2026-01-13完了)
  - forward filter rule 90/91: VPN→LAN/WAN禁止
  - VPNクライアントはVyOSのみアクセス可能
- [x] 3-4: WireGuardクライアント設定 (2026-01-13完了)
  - Mac: 10.10.10.2
  - iPhone: 10.10.10.3

### Phase 4: WXR隔離・IPv4ルーティング
→ [secrets/docs/phase4-wxr-routing.md](secrets/docs/phase4-wxr-routing.md)

- [x] 4-1: L2スイッチ経由でWXRをONUに接続 (2026-01-06完了)
- [x] 4-2: WXR MAP-E専用化 (完了)
  - LAN側IP: 192.168.100.1
  - DHCPサーバー: 無効
  - **重要**: 「インターネット@スタートを行う」(自動判別)を使用すること。「v6プラス」手動選択は動作しない
- [x] 4-3: 別セグメント構築 (完了)
  - eth0: 192.168.100.2/24
  - NAT source rule 100 設定済み
- [x] 4-4: IPv4ルーティング設定完了 (2026-01-06)
  - デフォルトルート: 0.0.0.0/0 via 192.168.100.1
  - LAN → WXR → MAP-E → インターネット 疎通確認済み

### Phase 5: 運用設定
→ [secrets/docs/phase5-operations.md](secrets/docs/phase5-operations.md)

- [x] 5-1: Cloudflare DDNS設定 (2026-01-13完了)
  - router.murata-lab.net → IPv6自動更新
  - eth1のIPv6アドレスを使用
- [x] 5-2: ファイアウォールログ設定 (2026-01-13完了)
  - input/forward filter default-log有効

### Phase 6: バックアップ体制
→ [secrets/docs/phase6-backup.md](secrets/docs/phase6-backup.md)

- [x] 6-1: VyOS設定バックアップ (完了)
  - 日次自動バックアップ: /config/scripts/backup.sh (毎日3:00)
  - 手動バックアップ: /config/backup-YYYYMMDD.txt
- [x] 6-2: WireGuard鍵バックアップ (2026-01-13完了)
  - Mac: ~/.wireguard/ に全鍵を保存

---

## リファレンス
→ [secrets/docs/reference.md](secrets/docs/reference.md)

- VyOS基本操作
- ルーティング方針
- ファイアウォールルール番号一覧
- 環境情報
- MAP-Eパラメータ（保険用）

---

## トラブルシューティング

- [IPv6疎通問題](secrets/docs/troubleshooting-ipv6.md) - チェックリスト、過去の失敗パターン、VyOS制約
- [DHCPv6-PD取得問題](secrets/docs/troubleshooting-dhcpv6-pd.md) - DUID-LL形式が必須
- [RA設定消失](secrets/docs/troubleshooting-ra-missing.md) - クライアントがIPv6取得できない場合の診断手順
- [カーネル更新失敗](secrets/docs/failure-log-2026-01-07-kernel-update.md) - MODULE_SIG_FORCE問題

---

## 復旧用リソース

→ **[secrets/docs/disaster-recovery.md](secrets/docs/disaster-recovery.md)** - 災害復旧ガイド (詳細手順)

| ファイル | 用途 |
|----------|------|
| `secrets/scripts/vyos-restore.env.example` | シークレット値テンプレート |
| `secrets/scripts/generate-vyos-restore.sh` | vbashスクリプト生成ツール |
| `secrets/scripts/recovery-vyos-config.sh` | 手動復元用の手順表示 |
| `secrets/scripts/backup-vyos-config.txt` | 設定コマンド一覧 (参照用) |

---

## VyOS コマンド注意事項

### VyOS と Linux の違い

VyOSはDebianベースだが、一部コマンドの構文が異なる:

```bash
# ping (VyOSでは -c オプションなし)
ping 8.8.8.8 count 3        # VyOS構文
# ping -c 3 8.8.8.8         # Linux構文 (VyOSでは動作しない)

# tcpdump (sudo必須、フィルタはシングルクォート)
sudo tcpdump -i eth1 -n 'ip6 proto 4'
```

### コマンド指示時の必須ルール

1. **関連コマンドは全て一度に提示する** (例: tcpdump + ping を同時に)
2. **ターミナル2つ必要な場合は明示する**
3. **VyOS固有の構文を使う** (上記参照)
4. **暫定対応か恒久対応かを必ず明示する**
   - **暫定対応**: 再起動で消える、一時的な検証用
   - **恒久対応**: 永続化される、本番運用向け
   - 例: 「これは**暫定対応**です。再起動で消えます。」

### 選択肢提示時の必須ルール

複数の選択肢を提示する際は、**必ずメリット・デメリットを両方記載する**。
一方的な推奨や、メリットだけ/デメリットだけの説明は禁止。

---

## VyOS構文メモ (バージョン依存)

### DHCPv4サーバー設定 (VyOS 1.4+)

```bash
# subnet-id が必須
set service dhcp-server shared-network-name LAN subnet 192.168.1.0/24 subnet-id 1

# オプションは "option" の下に配置
set service dhcp-server shared-network-name LAN subnet 192.168.1.0/24 option default-router 192.168.1.1
set service dhcp-server shared-network-name LAN subnet 192.168.1.0/24 option name-server 8.8.8.8

# 旧構文 (動作しない)
# set service dhcp-server ... default-router 192.168.1.1  ← NG
# set service dhcp-server ... name-server 8.8.8.8        ← NG
```

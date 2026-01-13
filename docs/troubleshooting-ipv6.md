# IPv6トラブルシューティング

## チェックリスト

IPv6が疎通しない場合、以下の順に確認する。

### 1. eth1にIPv6アドレスがあるか

```bash
ip -6 addr show eth1
```

- リンクローカル (fe80::) すらない → `no-default-link-local` が設定されている
- グローバルがない → DHCPv6-PDが動作していない

### 2. DHCPv6-PDでプレフィックスを取得できているか

```bash
show ipv6 route
```

`2404:7a82:4d02:41xx::/64` がeth2に付いているか確認。

### 3. デフォルトルートが正しいか

```bash
show ipv6 route
```

`::/0` がeth1経由でNGNを向いているか確認。

- `K>*` (Kernelルート) が `S` (Static) より優先されていたらWXRのRAが原因

### 4. NGNゲートウェイにpingできるか

```bash
ping6 fe80::a611:bbff:fe7d:ee11%eth1 -c 3
```

### 5. 物理接続

eth1 → LXW-10G5 → ONU の経路が正しいか確認。

---

## 過去に発生した問題と対処

| 症状 | 原因 | 対処 |
|------|------|------|
| eth1にIPv6アドレスがない | `no-default-link-local` 設定 | `delete interfaces ethernet eth1 ipv6 address no-default-link-local` |
| Kernelルートが優先される | WXRがRAを送信 | WXRをAPモードにし、WANポートからケーブルを抜く |
| `ping6: System error` | DNS解決失敗 | IPアドレスで直接テスト `ping6 2001:4860:4860::8888` |
| DHCPv6-PDでプレフィックス取得できない | リンクローカルがない/DUIDが間違っている | 上記1を確認、DUID-LL形式を確認 |
| `ipv6 address` が空ブロックで残る | `no-default-link-local` 削除後の残骸 | `delete interfaces ethernet eth1 ipv6 address` で空ブロックを削除 |
| static route6のゲートウェイが間違っている | WXRのMACをNGNと勘違い | `sudo rdisc6 eth1` で正しいゲートウェイを確認 |

---

## NGNゲートウェイの確認方法

```bash
sudo rdisc6 eth1
```

出力の `from fe80::xxxx` がNGNゲートウェイのリンクローカルアドレス。

**正しいNGNゲートウェイ**: `fe80::a611:bbff:fe7d:ee11` (MAC: `A4:11:BB:7D:EE:11`)

---

## VyOS環境の制約

### 使えないコマンド

| コマンド | 代替手段 |
|----------|----------|
| `xxd` | `od -A x -t x1z` または `hexdump -C` |

### 使えないサービス名

| コマンド | 備考 |
|----------|------|
| `systemctl restart dhcp6c` | VyOSではdhcp6c.serviceは存在しない。設定を再適用する場合は `commit` またはインターフェース再起動 (`ip link set ethX down && ip link set ethX up`) |

### VyOS構文の変更 (Rolling Release)

| 旧構文 | 新構文 |
|--------|--------|
| `set system ntp server <server>` | `set service ntp server <server>` |

### DHCPv6-PD関連

- **DUIDファイル形式**: `/var/lib/dhcpv6/dhcp6c_duid` は先頭2バイトがリトルエンディアンの長さ
  - 例: 10バイトのDUIDなら `\x0a\x00` + DUID本体
- **DUID-LL形式**: `00:03:00:01:MAC` (NTT NGNはこの形式が必須)
- **設定ファイルの`send client-id`**: DUIDファイルより優先されるため、DUIDファイルを使う場合は`send client-id`行を削除した設定ファイルを使用

### IPv6リンクローカルアドレス

- **`no-default-link-local` を設定するとIPv6が動作しない**: リンクローカルアドレスがないとDHCPv6-PDもRAも受信できない
- DHCPv6-PDを使う場合は `no-default-link-local` を削除すること

### WXR9300BE6P APモード時の注意

- **APモードでもWANポートにケーブルが刺さっているとRAを送信する可能性がある**
- APモードにする場合はWANポートからケーブルを抜くこと

---

## BIGLOBE 10ギガプランの制約

- **PPPoE接続不可**: 10ギガプラン(ファミリー10ギガタイプ)ではPPPoE接続は対象外
- **IPv6オプションのみ**: IPoE + MAP-E相当の方式でのみIPv4接続可能
- **DHCPv6-PD競合**: NGNは/56を1つしか払い出さないため、VyOSとWXRで競合する

---

## IPv4 over MAP-E のMTU/MSS問題

### 症状

- `git push` (HTTPS) で `SSL connection timeout` が頻発
- `ping -D -s 1472 github.com` で `frag needed and DF set (MTU 1452)` が返る
- SSH (IPv6) は正常だがHTTPS (IPv4) だけ不安定

### 原因

MAP-Eトンネル (IPv4 over IPv6) のカプセル化オーバーヘッドでMTUが減少。
Path MTU Discovery (PMTUD) が正しく動作しないと、SSL/TLSハンドシェイクの大きなパケットがタイムアウトする。

### 解決策: MSS Clamping

**[VyOS 2024.x / 2026.x]** インターフェースレベルでMSS調整:

```bash
configure
set interfaces ethernet eth0 ip adjust-mss clamp-mss-to-pmtu
commit
save
```

- `eth0`: WXR (MAP-E) 向けインターフェース
- `clamp-mss-to-pmtu`: PMTUに基づいてTCP MSSを自動調整

### 動作しない構文 (VyOS 2024+)

以下の構文は**古いVyOSの構文**であり、VyOS 2024.x以降では使えない:

```bash
# NG: firewall options は存在しない
set firewall options interface eth0 adjust-mss clamp-mss-to-pmtu

# NG: policy route でMSS設定 + interfaceへの適用ができない
set policy route MSS-CLAMP rule 10 set tcp-mss 1412
set interfaces ethernet eth0 policy route MSS-CLAMP
```

### 確認方法

設定後、Macから以下を実行:

```bash
# MTU問題が解消されたか確認
curl -4 -v https://github.com 2>&1 | grep -E "(Connected|SSL)"

# pingでフラグメント確認 (エラーが出なくなるはず)
ping -c 3 -D -s 1400 github.com
```

### 補足: GitHubはIPv6非対応

GitHubはHTTPS接続にIPv6アドレスを提供していない:

```bash
dig AAAA github.com  # 結果なし
```

| 方式 | プロトコル | IPv6対応 |
|------|-----------|----------|
| HTTPS + トークン | TCP/443 | IPv4のみ |
| SSH + 鍵認証 | TCP/22 | **IPv6対応** |
| `gh` CLI | HTTPS | IPv4のみ |

**推奨**: 普段の `git push/pull` はSSHに切り替え、IPv6で高速通信:

```bash
git remote set-url origin git@github.com:USER/REPO.git
```

# IPv6 トラブルシューティング

VyOS IPv6接続に関するトラブルシューティングガイド。

---

## よくある問題

### 1. IPv6で外部に繋がらない (LAN側クライアント)

**症状**: `curl -6 https://ifconfig.co` がタイムアウト

**最も可能性が高い原因**: **WANとLANで同じ/64プレフィックスを使用している**

#### 確認手順

```bash
# [VyOS] ルーティングテーブル確認
ip -6 route show | grep "/64"
```

**問題のある出力例**:
```
2404:7a82:4d02:4100::/64 dev eth2 proto kernel metric 256
2404:7a82:4d02:4100::/64 dev eth1 proto kernel metric 256  # 重複！
```

同じプレフィックスがeth1 (WAN) とeth2 (LAN) の両方にある場合、戻りパケットが正しいインターフェースに届かない。

#### 原因

- eth1 (WAN): ISPからDHCPv6-PDで/56を取得し、SLAACで/64アドレスを自動取得
- eth2 (LAN): 同じ/64をRAで配布している

カーネルは同じ宛先に対して複数のルートがあると、正しいインターフェースを選択できない。

#### 解決方法

**LANには/56の別の/64サブネットを使用する**:

```bash
# [VyOS] 設定モードに入る
configure

# 例: WANが4100を使っている場合、LANは4101を使用
delete service router-advert interface eth2 prefix 2404:7a82:4d02:4100::/64
set service router-advert interface eth2 prefix 2404:7a82:4d02:4101::/64

# eth2のIPv6アドレスも変更
set interfaces ethernet eth2 address 2404:7a82:4d02:4101::1/64

commit
save
exit
```

```bash
# [Mac] IPv6アドレス更新
sudo ifconfig en0 down && sudo ifconfig en0 up

# [Mac] 新しいアドレス確認
ifconfig en0 | grep inet6

# [Mac] 接続テスト
curl -6 -s https://ifconfig.co
```

#### サブネット割り当て例

/56プレフィックス (例: `2404:7a82:4d02:4100::/56`) から256個の/64が使用可能:

| サブネット | 用途 |
|------------|------|
| 4100::/64 | WAN (ISP自動割り当て) |
| 4101::/64 | LAN (クライアント向け) |
| 4102::/64 | (将来用: ゲストネットワーク等) |

---

### 2. RAが配布されない

**症状**: クライアントがIPv6アドレスを取得できない

**確認手順**:

```bash
# [VyOS] RA設定確認
show configuration commands | grep router-advert

# [VyOS] RAデーモン状態確認
ps aux | grep radvd
```

**対処**: RA設定が正しいか確認し、commit/saveを実行。

---

### 3. IPv6 DNS解決できない

**症状**: IPv6アドレスは取得できるが、名前解決ができない

**確認手順**:

```bash
# [Mac] DNS設定確認
scutil --dns | grep nameserver

# [VyOS] RDNSS設定確認
show configuration commands | grep name-server
```

**対処**: RAでRDNSSを配布:

```bash
# [VyOS]
set service router-advert interface eth2 name-server 2606:4700:4700::1111
set service router-advert interface eth2 name-server 2001:4860:4860::8888
```

---

## デバッグコマンド

### ルーティング確認

```bash
# [VyOS] IPv6ルーティングテーブル
ip -6 route show

# [VyOS] 特定アドレスへのルート確認
ip -6 route get 2001:4860:4860::8888
```

### インターフェース確認

```bash
# [VyOS] 全インターフェースのIPv6アドレス
ip -6 addr show

# [VyOS] 特定インターフェースのみ
ip -6 addr show eth1
ip -6 addr show eth2
```

### パケットキャプチャ

```bash
# [VyOS] WAN側のIPv6パケット
sudo tcpdump -i eth1 -n ip6

# [VyOS] LAN側のIPv6パケット
sudo tcpdump -i eth2 -n ip6
```

### conntrack確認

```bash
# [VyOS] IPv6接続トラッキング
sudo conntrack -L -f ipv6 | head -20
```

---

## 関連ドキュメント

- [CLAUDE.md](../CLAUDE.md) - プロジェクト概要
- [troubleshooting-mape.md](troubleshooting-mape.md) - MAP-Eトラブルシューティング

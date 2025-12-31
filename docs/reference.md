# リファレンス

## VyOS基本操作

```bash
# 設定モードに入る
configure

# 設定を適用(まだ保存しない)
commit

# 設定を永続化
save

# 設定モードを抜ける
exit

# 現在の設定を表示
show configuration

# インターフェース状態確認
show interfaces

# ルーティングテーブル確認
show ip route
show ipv6 route
```

---

## ルーティング方針

```
# デフォルトルート
# IPv6 → ISP(直行) - autoconfで自動設定
# IPv4 → blackhole(基本)
set protocols static route 0.0.0.0/0 blackhole

# 例外IPv4: policy-based routing または static route でWXRへ転送
set protocols static route <target>/32 next-hop 192.168.100.1
```

---

## ファイアウォールルール番号一覧

### WAN6_IN（eth0 inbound）

| ルール# | 用途 | 設定タスク |
|---------|------|------------|
| 10 | established/related許可 | 2-3 |
| 20-24 | ICMPv6（必須タイプのみ） | 2-3 |
| 25 | WireGuard rate limit | 3-2 |
| 30 | WireGuard許可 | 3-2 |
| default | drop + log | 2-3, 5-2 |

---

## 環境情報

- **OS**: VyOS Rolling Release (無償版、Debian 12ベース)
  - ダウンロード: https://vyos.net/get/nightly-builds/
  - ドキュメント: https://docs.vyos.io/
- **NIC**: Intel X540-T2 (10GbE)
- **L2スイッチ**: BUFFALO LXW-10G5 (10GbE 5ポート、ONU直下で分岐用)
- **ISP**: BIGLOBE (IPv6 IPoE + MAP-E)
- **既存ルーター**: Buffalo WXR9300BE6P (10Gポート×1, 2.5Gポート×1, 1Gポート×4)

### 速度目標

| プロトコル | 経路 | 目標速度 |
|-----------|------|----------|
| IPv6 | 自作ルーター → LXW-10G5 → ONU → NGN | 10Gbps狙い |
| IPv4 | 自作ルーター → WXR → MAP-E | 2〜3Gbps期待 |

---

## 参考: 以前のMAP-E自作パラメータ(保険用)

- MAC偽装: f0:f8:4a:67:58:00
- CE: 2404:7a82:4d02:4100:85:d10d:200:4100
- BR: 2001:260:700:1::1:275
- IPv4: 133.209.13.2
- ポート: 5136-5151

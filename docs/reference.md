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

### IPv6 forward filter (eth1 inbound)

VyOS 2024.x以降の新構文: `firewall ipv6 forward filter`

| ルール# | 用途 | 設定タスク |
|---------|------|------------|
| 10 | established/related許可 | 2-3 |
| 20 | echo-request許可 | 2-3 |
| 21 | nd-neighbor-solicit許可 | 2-3 |
| 22 | nd-neighbor-advert許可 | 2-3 |
| 23 | nd-router-solicit許可 | 2-3 |
| 24 | nd-router-advert許可 | 2-3 |
| 25 | WireGuard rate limit | 3-2 |
| 30 | WireGuard許可 | 3-2 |
| default | drop | 2-3 |

**注意**: 各ルールに `inbound-interface name eth1` を指定

---

## 環境情報

### ハードウェア

**自作ルーター本体**: HP ProDesk 600 G4 SFF
- CPU: Intel Core i5-8500 (6コア)
- RAM: 8GB DDR4-2666
- ストレージ: 2.5インチ SATA SSD (VyOS用に換装)
- 拡張スロット: PCIe x16, PCIe x1, M.2 2280 NVMe

**追加NIC 1**: Intel X540-T2 (10GbE, PCIe x8) → PCIe x16スロット
- ポート数: 2
- Port1 (enp1s0f0): WAN (LXW-10G5へ)
- Port2 (enp1s0f1): LAN

**追加NIC 2**: Binardat RTL8126 (5GbE, PCIe x1) → PCIe x1スロット
- フレキシブル用途 (Mac/Proxmox等、必要時に接続)
- VyOS設定には含めない
- 対応速度: 5G/2.5G/1G/100Mbps
- ロープロファイル対応

**内蔵NIC**: Intel I219-LM (1GbE)
- WXR接続用 (IPv4転送、別セグメント 192.168.100.x)
- デバイス名: 要確認 (VyOSインストール後に `show interfaces` で確認)

### ネットワーク機器

- **L2スイッチ**: BUFFALO LXW-10G5 (10GbE 5ポート、ONU直下で分岐用)
- **既存ルーター**: Buffalo WXR9300BE6P (10Gポート×1, 1Gポート×4)

### ソフトウェア

- **OS**: VyOS Rolling Release (無償版、Debian 12ベース)
  - ダウンロード: https://vyos.net/get/nightly-builds/
  - ドキュメント: https://docs.vyos.io/

### ISP

- **ISP**: BIGLOBE (IPv6 IPoE + MAP-E)
- **回線**: 10Gbps

### インターフェース名の確認

VyOSインストール後、実際のインターフェース名を確認:
```bash
show interfaces
```

**確定したインターフェース対応表**:
| VyOS名 | altname | MAC | NIC | 速度 | 用途 |
|--------|---------|-----|-----|------|------|
| eth0 | - | f4:39:09:1f:ef:aa | オンボード | 1GbE | WXR接続 (別セグメント 192.168.100.x) |
| eth1 | enp1s0f1 | c4:62:37:08:0e:53 | Intel X540-T2 Port2 | 10GbE | WAN (LXW-10G5経由でONU) |
| eth2 | enp1s0f0 | c4:62:37:08:0e:52 | Intel X540-T2 Port1 | 10GbE | LAN (主要機器向け) |

**注意**: VyOSでは `eth0`, `eth1`, `eth2` という命名になる。`show interfaces ethernet ethX` で `altname` を確認可能。

### WXR接続用別セグメント (192.168.100.x)

自作ルーターとWXR9300BE6Pを1GbEオンボードNICで直結し、IPv4転送専用の別セグメントを構築する。

- 自作ルーター側: 192.168.100.2/24
- WXR側 (LAN): 192.168.100.1/24 (DHCPサーバー無効)
- 用途: IPv4トラフィックをWXR経由でMAP-Eに転送
- 帯域: 1Gbps上限 (IPv4は例外扱いなので問題なし)

### 速度目標

| プロトコル | 経路 | 目標速度 |
|-----------|------|----------|
| IPv6 | 自作ルーター → LXW-10G5 → ONU → NGN | 10Gbps狙い |
| IPv4 | 自作ルーター → WXR → MAP-E | 1Gbps上限 |

---

## 参考: 以前のMAP-E自作パラメータ(保険用)

- MAC偽装: f0:f8:4a:67:58:00
- CE: 2404:7a82:4d02:4100:85:d10d:200:4100
- BR: 2001:260:700:1::1:275
- IPv4: 133.209.13.2
- ポート: 5136-5151

# ハードウェア仕様書

本プロジェクトで使用する機材の詳細スペックをまとめる。

---

## 自作ルーター本体

### HP ProDesk 600 G4 SFF

| 項目 | 仕様 |
|------|------|
| フォームファクタ | Small Form Factor (SFF) |
| CPU | Intel Core i5-8500 (6コア, 最大4.1GHz) |
| RAM | 8GB DDR4-2666 |
| ストレージ | 2.5インチ SATA SSD (VyOS用に換装) |
| 電源 | 180W (92%効率, Active PFC) |

#### 拡張スロット

| スロット | 仕様 | 使用状況 |
|---------|------|---------|
| PCIe 3.0 x16 | フルハイト/ロープロファイル | Intel X540-T2 使用中 |
| PCIe 3.0 x4 | ロープロファイル | RTL8126 NIC 使用中 |
| M.2 2280 | PCIe NVMe / SATA | 空き |
| M.2 2230 | PCIe x1 (Wi-Fi用) | 空き |

#### 注意事項
- 電源が180Wのため、高消費電力GPUは使用不可
- PCIeスロットから最大75W供給可能

**参考**: [HP ProDesk 600 G4 SFF Specs](https://www.hardware-corner.net/desktop-models/HP-ProDesk-600-G4-SFF/)

---

## NIC (ネットワークインターフェースカード)

### Intel X540-T2 (10GbE)

| 項目 | 仕様 |
|------|------|
| コントローラ | Intel X540 |
| ポート数 | 2x RJ-45 |
| 速度 | 10GbE / 1GbE / 100Mbps |
| インターフェース | PCIe 2.0 x8 (x16スロットで使用) |
| 消費電力 | 約15W |
| サイズ | 6.00 x 4.00 x 1.00 インチ |
| 冷却 | ヒートシンク (40x40mm) 取り付け済み |

#### VyOSでの認識

| VyOS名 | altname | MAC | 用途 |
|--------|---------|-----|------|
| eth1 | enp1s0f1 | c4:62:37:08:0e:53 | WAN (LXW-10G5経由) |
| eth2 | enp1s0f0 | c4:62:37:08:0e:52 | LAN |

**参考**: [Intel X540-T2 Support](https://www.intel.com/content/www/us/en/support/products/58954/ethernet-products/500-series-network-adapters-up-to-10gbe/intel-ethernet-converged-network-adapter-x540/intel-ethernet-converged-network-adapter-x540-t2.html)

---

### Realtek RTL8126 (5GbE)

| 項目 | 仕様 |
|------|------|
| コントローラ | Realtek RTL8126-CG |
| ポート数 | 1x RJ-45 |
| 速度 | 5GbE / 2.5GbE / 1GbE / 100Mbps |
| インターフェース | PCIe 3.0 x1 |
| 消費電力 | 3W未満 |
| 対応ケーブル | Cat 5e以上 |
| 機能 | Wake-on-LAN (WOL), Auto-Negotiation |

#### 特徴
- 低消費電力で発熱が少ない
- Cat 5eケーブルで5Gbps対応
- 2025年 Taiwan Excellence Award受賞

#### 現在の用途
- VyOS設定には含めない (フレキシブル用途)
- 将来的にeth0 (1GbE) の代替としてWXR接続を5Gbps化する予定

**参考**: [Realtek RTL8126-VB](https://www.realtek.com/Product/ProductHitsDetail?id=4425&menu_id=643)

---

### Intel I219-LM (1GbE, オンボード)

| 項目 | 仕様 |
|------|------|
| コントローラ | Intel I219-LM |
| ポート数 | 1x RJ-45 |
| 速度 | 1GbE / 100Mbps |
| インターフェース | オンボード (PCH統合) |

#### VyOSでの認識

| VyOS名 | MAC | 用途 |
|--------|-----|------|
| eth0 | f4:39:09:1f:ef:aa | WXR接続 (192.168.100.x) |

---

## ネットワーク機器

### BUFFALO LXW-10G5 (10GbE L2スイッチ)

| 項目 | 仕様 |
|------|------|
| ポート数 | 5x RJ-45 |
| 対応速度 | 10GbE / 5GbE / 2.5GbE / 1GbE / 100Mbps |
| スイッチングファブリック | 100Gbps |
| MACアドレステーブル | 約16,000件 |
| ジャンボフレーム | 12,288 Bytes |
| 消費電力 | 最大27W |
| 冷却 | スマート冷却ファン内蔵 |
| 外形寸法 | 180 x 34 x 145 mm |
| 重量 | 約0.9kg |

#### 対応規格
- IEEE 802.3an (10GBASE-T)
- IEEE 802.3bz (5GBASE-T / 2.5GBASE-T)
- IEEE 802.3ab (1000BASE-T)
- IEEE 802.3u (100BASE-TX)

#### 機能
- Auto-Negotiation
- Auto-MDI/MDIX
- IEEE 802.3x フローコントロール
- ループ検出機能
- IEEE 802.3az (EEE) 省電力
- EAPOL/BPDU フレーム透過

#### MACアドレス
`EC:5A:31:06:19:AD`

#### 用途
ONU直下でVyOS、WXR、その他機器へ10GbE分岐

**参考**: [BUFFALO LXW-10G5](https://www.buffalo.jp/product/detail/lxw-10g5.html)

---

### BUFFALO WXR9300BE6P (Wi-Fi 7ルーター)

| 項目 | 仕様 |
|------|------|
| 動作モード | ルーターモード / APモード |
| WANポート | 1x 10GbE RJ-45 |
| LANポート | 4x 1GbE RJ-45 |
| Wi-Fi規格 | Wi-Fi 7 (IEEE 802.11be) |
| Wi-Fi速度 | 5764 + 2882 + 688 Mbps (トライバンド) |
| ストリーム数 | 6ストリーム |

#### 有線ポート詳細

| ポート | 速度 | 用途 |
|--------|------|------|
| INTERNET | 10GbE | LXW-10G5経由でONU接続 |
| LAN1-4 | 1GbE | VyOS (eth0) / Mac接続 |

#### MACアドレス
- 有線: `F0:F8:4A:67:58:00`
- IPv6リンクローカル: `fe80::f2f8:4aff:fe67:5800`

#### 現在の設定
- LAN側IP: 192.168.100.1/24
- DHCPサーバー: 無効
- 接続方式: インターネット@スタートを行う (MAP-E自動判別)

**重要**: 「v6プラス」手動選択は動作しない。必ず「インターネット@スタートを行う」を使用すること。

**参考**: [BUFFALO WXR9300BE6P](https://www.buffalo.jp/product/detail/manual/wxr9300be6p.html)

---

### NTT ONU (10G-EPON)

| 項目 | 仕様 |
|------|------|
| 回線種別 | フレッツ光クロス (10Gbps) |
| ポート | 1x 10GbE RJ-45 |
| MACアドレス | `00:11:57:A8:CA:68` |

---

## NGNゲートウェイ

| 項目 | 値 |
|------|-----|
| MACアドレス | `A4:11:BB:7D:EE:11` |
| IPv6リンクローカル | `fe80::a611:bbff:fe7d:ee11` |
| 役割 | RAで広告されるデフォルトゲートウェイ |

**注意**: WXR (`F0:F8:4A:67:58:00`) と混同しないこと。

---

## 物理接続図

```
[ONU] ─── 10G ─── [LXW-10G5] ───┬─── 10G ─── [VyOS eth1] WAN
  │                             │
  │                             ├─── 10G ─── [VyOS eth2] LAN ─── [Mac/PC]
  │                             │
  │                             └─── 10G ─── [WXR INTERNET]
  │
  └─ MACアドレス: 00:11:57:A8:CA:68

[VyOS eth0] ─── 1G ─── [WXR LAN1] ─── [Mac WXR@LAN]
  192.168.100.2         192.168.100.1    192.168.100.60
```

---

## MACアドレス一覧

| 機器 | MACアドレス | IPv6リンクローカル | 備考 |
|------|-------------|-------------------|------|
| ONU | `00:11:57:A8:CA:68` | - | NTT |
| LXW-10G5 | `EC:5A:31:06:19:AD` | - | L2スイッチ |
| WXR9300BE6P | `F0:F8:4A:67:58:00` | `fe80::f2f8:4aff:fe67:5800` | ルーター |
| NGNゲートウェイ | `A4:11:BB:7D:EE:11` | `fe80::a611:bbff:fe7d:ee11` | ISP側 |
| VyOS eth0 | `f4:39:09:1f:ef:aa` | - | オンボード |
| VyOS eth1 | `c4:62:37:08:0e:53` | `fe80::c662:37ff:fe08:e53` | X540 Port2 |
| VyOS eth2 | `c4:62:37:08:0e:52` | - | X540 Port1 |

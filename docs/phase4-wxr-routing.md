# Phase 4: WXR隔離・IPv4ルーティング

## タスク4-1: LXW-10G5経由でWXRをONUに接続

**目的**: WXRがONUと同一L2でIPv6を取得できる状態にする

**物理構成**:
```
[ONU] ─────┬─ [LXW-10G5] ─┬─ 10G ── [自作ルーター eth0(WAN)]
           │              │                    │
           │              │              [eth1(LAN)] ── [LAN機器]
           │              │                    │
           │              │              [eth2] ── (4-3で使用)
           │              │
           └──────────────┴─ 10G ── [WXR9300BE6P 10Gポート(WAN)]
```

**LXW-10G5ポート割り当て例**:
| ポート | 接続先 | 備考 |
|--------|--------|------|
| 1 | ONU | 10GbE |
| 2 | 自作ルーター eth0 | 10GbE (WAN) |
| 3 | WXR 10Gポート | 10GbE (MAP-E WAN) |
| 4-5 | 予備 | - |

**手順**:
1. LXW-10G5ポート1をONUに接続
2. 自作ルーターWANポート(eth0)をLXW-10G5ポート2に接続
3. WXR 10GポートをLXW-10G5ポート3に接続

**注意点**:
- LXW-10G5はL2スイッチ(VLAN機能なし)なので、この時点で全機器が同一L2
- WXR9300BE6Pの10Gポートは1つのみ(WANに使用)

**完了条件**: 両機器がONUと通信可能(IPv6アドレス取得)

---

## タスク4-2: WXR MAP-E専用化

**目的**: WXRをMAP-E CE専用機として隔離

**手順**:
1. WXR管理画面でDHCPv6-PDを**OFF**
2. WXR LAN側のRA配布を**OFF**
3. MAP-E接続が維持されていることを確認

**注意点**:
- IPv6フィルタは最小限(MAP-Eに必要なもののみ)

**完了条件**: PD OFF, RA OFF, MAP-E維持

---

## タスク4-3: 別セグメント構築

**目的**: IPv4転送用の専用経路を確保

**構成図**:
```
[自作ルーター]                      [WXR9300BE6P]
    │                                   │
  eth2 ──────────────────────────── LAN側ポート
192.168.100.2/24                  192.168.100.1/24
                                  (DHCPサーバー無効)
```

**IP設計**:
| 機器 | インターフェース | IPアドレス | 役割 |
|------|------------------|------------|------|
| WXR | LAN側(2.5G or 1G) | 192.168.100.1/24 | IPv4 GW |
| 自作ルーター | eth2 | 192.168.100.2/24 | IPv4転送元 |

**手順**:

### 4-3-1. WXR側設定(管理画面)
1. WXR管理画面にアクセス
2. LAN側IPを `192.168.100.1` に変更
3. DHCPサーバーを**無効化**
4. 設定を保存

### 4-3-2. 物理接続
1. 自作ルーターの eth2 (RTL8126 5GbE) をWXRの2.5Gポートに接続
   - WXRの10Gポートは既にWAN(MAP-E)で使用中
   - 5GbE NICは2.5Gにオートネゴシエーションで対応
   - MAP-Eの速度(2〜3Gbps)を十分に活かせる

### 4-3-3. VyOS側設定
```
configure

set interfaces ethernet eth2 description 'To WXR LAN (IPv4 transit)'
set interfaces ethernet eth2 address 192.168.100.2/24

commit
save
```

### 4-3-4. 疎通確認
```bash
# WXRへのping
ping 192.168.100.1

# WXR経由でインターネットIPv4疎通確認
# (4-4設定後に確認)
```

**注意点**:
- このセグメントはIPv4専用、IPv6は流さない
- WXRのDHCPは無効にする(自作ルーターは静的IP)

**完了条件**:
- [ ] 自作ルーター(192.168.100.2) → WXR(192.168.100.1) ping成功
- [ ] eth2が正しく認識されている(`show interfaces`)

---

## タスク4-4: IPv4ルーティング

**目的**: IPv4トラフィックをWXR経由で処理

### 4-4-1. 初期設定（全IPv4→WXR転送）

まずは全てのIPv4をWXR経由にして動作確認:

```
configure

set protocols static route 0.0.0.0/0 next-hop 192.168.100.1

commit
save
```

**確認**:
```bash
# ルーティングテーブル確認
show ip route

# IPv4サイトへの疎通確認
ping 8.8.8.8
curl -4 ifconfig.me  # グローバルIPv4確認
```

### 4-4-2. LAN側のIPv4 NAT設定

LAN側クライアントがIPv4でインターネットに出られるようにする:

```
configure

# LAN側インターフェースのIPv4アドレス設定
set interfaces ethernet eth1 address 192.168.1.1/24

# LAN → WXR方向のNAT(マスカレード)
set nat source rule 100 outbound-interface name eth2
set nat source rule 100 source address 192.168.1.0/24
set nat source rule 100 translation address masquerade

commit
save
```

**確認**:
```bash
# LANクライアントからIPv4サイトにアクセスできるか確認
```

### 4-4-3. (オプション) blackhole + 例外ルート

安定運用後、IPv4を最小限にしたい場合:

```
configure

# デフォルトをblackholeに変更
delete protocols static route 0.0.0.0/0 next-hop 192.168.100.1
set protocols static route 0.0.0.0/0 blackhole

# 例外: 特定宛先のみWXR経由
# 例: 銀行サイト、IPv4-onlyサービス等
set protocols static route <IPv4-only宛先>/32 next-hop 192.168.100.1

commit
save
```

**注意点**:
- blackholeの代替: `reject`でICMP unreachable返却も可
- 例外リストは段階的に追加
- `show log`で何が落ちているか確認して調整

**完了条件**:
- [ ] LANクライアントからIPv4サイトにアクセス可能
- [ ] `curl -4 ifconfig.me`でMAP-E経由のIPv4アドレスが表示される
- [ ] IPv6サイトはWXRを経由せず直接通信できている

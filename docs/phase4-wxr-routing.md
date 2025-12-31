# Phase 4: WXR隔離・IPv4ルーティング

## タスク4-1: LXW-10G5経由でWXRをONUに接続

**目的**: WXRがONUと同一L2でIPv6を取得できる状態にする

**物理構成**:
```
[ONU] ── [LXW-10G5] ─┬─ 10G ── [自作ルーター]
                     └─ 10G ── [WXR9300BE6P]
```

**手順**:
1. LXW-10G5をONUに接続
2. 自作ルーターWANポートをLXW-10G5に接続 (10G)
3. WXR WANポートをLXW-10G5に接続 (10G)

**注意点**:
- この時点でWXRと自作ルーターは同一L2(後で論理分離)
- WXR9300BE6Pの10Gポートを使用

**完了条件**: 両機器がONUと通信可

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

**手順**:
1. 自作ルーターに追加インターフェース(物理 or VLAN)
2. WXR LAN側と接続(例: 192.168.100.0/24)
3. 疎通確認(自作ルーター → WXR → インターネットIPv4)

**注意点**:
- このセグメントはIPv4専用、IPv6は流さない

**完了条件**: 自作ルーター→WXR→IPv4疎通

---

## タスク4-4: IPv4ルーティング

**目的**: IPv4トラフィックをWXR経由で処理

### 4-4-1. 初期設定（全IPv4→WXR転送）

```
configure

set protocols static route 0.0.0.0/0 next-hop 192.168.100.1

commit
save
```

**確認**: IPv4サイトにアクセス可能か確認

### 4-4-2. 安定後（blackhole + 例外ルート）

```
configure

# デフォルトをblackholeに
set protocols static route 0.0.0.0/0 blackhole

# 例外: 特定宛先のみWXR経由
set protocols static route <IPv4-only宛先>/32 next-hop 192.168.100.1

commit
save
```

**注意点**:
- blackholeの代替: `reject`でICMP unreachable返却も可
- 例外リストは段階的に追加
- `show log`で何が落ちているか確認して調整

**完了条件**: IPv6優先、IPv4は例外のみ

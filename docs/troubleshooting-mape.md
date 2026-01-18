# MAP-E トラブルシューティング

VyOS直接MAP-E接続に関するトラブルシューティングガイド。

---

## よくある問題

### 1. IPv4に繋がらなくなった (最重要)

**症状**: 突然IPv4インターネット接続ができなくなった

**最も可能性が高い原因**: **DHCPv6-PDプレフィックスの変更**

#### 確認手順

```bash
[VyOS] show interfaces ethernet eth1
```

現在のIPv6アドレスを確認し、`scripts/setup-mape.sh` に設定したプレフィックスと比較。

**プレフィックスが変わっている場合**:

1. MAP-Eパラメータを再計算: http://ipv4.web.fc2.com/map-e.html
2. `scripts/setup-mape.sh` のパラメータを更新
3. スクリプトを再実行

#### なぜプレフィックスが変わるのか

- ISPの設備変更
- ONUの交換・再起動
- 契約変更

**補足**: BIGLOBEのプレフィックスは通常安定していますが、保証はありません。

---

### 2. pingが通らない

**症状**: `ping 8.8.8.8` がタイムアウト

**原因**: MAP-Eの仕様 (正常動作)

MAP-Eではポート範囲が制限されているため、ICMPは正常に動作しません。

**確認方法**: curlを使用

```bash
[VyOS] curl -4 -I https://www.google.com
```

200/301/302が返れば正常です。

---

### 3. トンネルがUPしない

**症状**: `ip link show mape` でSTATE DOWN

**確認手順**:

```bash
# eth1のIPv6アドレス確認
[VyOS] show interfaces ethernet eth1

# BRへの疎通確認
[VyOS] ping 2001:260:700:1::1:275 count 3
```

**対処**:

1. eth1にIPv6アドレスがあるか確認
2. DHCPv6-PDが正常に動作しているか確認
3. NGNゲートウェイ (`scripts/setup-mape.sh` の `NGN_GATEWAY`) への疎通確認

---

### 4. 戻りパケットが来ない

**症状**: tcpdumpで送信は確認できるが応答がない

```bash
[VyOS] sudo tcpdump -i eth1 -n 'ip6 proto 4'
# → 送信のみ表示、応答なし
```

**原因候補**:

1. **rp_filter (Reverse Path Filter)**: 非対称ルーティングでパケット破棄

   ```bash
   # 確認
   [VyOS] cat /proc/sys/net/ipv4/conf/all/rp_filter

   # 緩和 (2 = loose mode)
   [VyOS] sudo sh -c 'echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter'
   [VyOS] sudo sh -c 'echo 2 > /proc/sys/net/ipv4/conf/eth1/rp_filter'
   ```

2. **BRアドレスの非対称性**: 送信先と応答元が異なる場合

   ```bash
   # remote any でトンネル再作成
   [VyOS] sudo ip -6 tunnel del mape
   [VyOS] sudo ip -6 tunnel add mape mode ip4ip6 \
       remote any \
       local <YOUR_CE_ADDRESS> \
       dev eth1
   ```

---

### 5. 特定のサイトに繋がらない

**症状**: 一部のサイトのみ接続できない

**原因**: ポート枯渇

MAP-Eでは240ポートしか使用できないため、多数の同時接続でポートが枯渇する可能性があります。

**確認**:

```bash
[VyOS] sudo conntrack -L | wc -l
```

240に近い場合はポート枯渇の可能性。

**対処**: 不要な接続を減らすか、時間をおいて再試行。

---

## デバッグコマンド

### トンネル状態

```bash
[VyOS] ip link show mape
[VyOS] ip addr show mape
[VyOS] ip -s link show mape  # 統計情報
```

### ルーティング

```bash
[VyOS] ip route show default
[VyOS] ip -6 route show dev eth1
[VyOS] ip -6 route get 2001:260:700:1::1:275
```

### パケットキャプチャ

```bash
# MAP-Eパケット (IPv4 in IPv6)
[VyOS] sudo tcpdump -i eth1 -n 'ip6 proto 4'

# BR宛パケット
[VyOS] sudo tcpdump -i eth1 -n 'ip6 and host 2001:260:700:1::1:275'

# mapeインターフェース
[VyOS] sudo tcpdump -i mape -n
```

### NAT状態

```bash
[VyOS] sudo conntrack -L
[VyOS] sudo nft list table ip vyos_nat
```

---

## MAP-Eパラメータ

`scripts/setup-mape.sh` で設定するパラメータ:

| パラメータ | 説明 | 計算方法 |
|-----------|------|----------|
| CE_ADDRESS | CE IPv6アドレス | DHCPv6-PDプレフィックスから計算 |
| BR_ADDRESS | BRアドレス | 東日本: `2001:260:700:1::1:275` |
| IPV4_ADDRESS | 割当IPv4アドレス | CE Addressから計算 |
| FIRST_PORT_RANGE | NAT用ポート範囲 | 240ポート中の最初のブロック |
| NGN_GATEWAY | NGNゲートウェイ | リンクローカルアドレス (fe80::で始まる) |

### パラメータ再計算

プレフィックスが変更された場合:

1. http://ipv4.web.fc2.com/map-e.html にアクセス
2. 新しいプレフィックスを入力
3. 計算結果で `scripts/setup-mape.sh` を更新

---

## 関連ドキュメント

- [CLAUDE.md](../CLAUDE.md) - プロジェクト概要
- [scripts/setup-mape.sh](../scripts/setup-mape.sh) - セットアップスクリプト

# トラブルシューティング: RA設定消失によるIPv6不通

## 発生日時

2026-01-12

## 症状

- MacからIPv4は通信可能 (MAP-E経由で133.209.13.2)
- MacからIPv6が通信不可 (ping6: No route to host)
- Fast.comでは540Mbps出るが、IPv4経由

## 診断結果

```bash
# Mac側: リンクローカルIPv6のみ、グローバルIPv6なし
[Mac] ifconfig en0 | grep inet6
inet6 fe80::1c43:afe0:5629:a3cf%en0 prefixlen 64 secured scopeid 0xb

# VyOS側: RA設定が存在しない
[VyOS] show configuration commands | grep router-advert
(空)

# VyOS自体はIPv6疎通OK
[VyOS] ping 2606:4700:4700::1111 count 3
→ 成功

# Mac側: WXRからRAを受信している (干渉)
[Mac] ndp -rn
fe80::f2f8:4aff:fe67:5800%en0  ← WXRのMAC F0:F8:4A:67:58:00 から生成
```

## 原因

VyOSの `service router-advert` 設定が消失していた (または最初から未設定だった)。

Phase 2-2完了済みとなっていたが、実際には設定が入っていなかった。

## 解決方法

```bash
[VyOS] configure

set service router-advert interface eth2 prefix 2404:7a82:4d02:4101::/64
set service router-advert interface eth2 name-server 2606:4700:4700::1111
set service router-advert interface eth2 name-server 2606:4700:4700::1001
set service router-advert interface eth2 name-server 2001:4860:4860::8888

commit
save
```

設定後、Macがグローバルipv6アドレス `2404:7a82:4d02:4101:...` を取得し、IPv6疎通成功。

## 教訓

1. **設定完了後は必ず `show configuration commands | grep XXX` で確認する**
2. **クライアントがIPv6を取得できない場合は `ndp -rn` でRAの送信元を確認**
3. **WXRのRA配布がONのままだと干渉する** - VyOSからRAを配布してもWXRのRAも届くため、クライアントが混乱する可能性あり

## 関連ドキュメント

- [Phase 2: IPv6基盤構築](phase2-ipv6.md)
- [リファレンス](reference.md)

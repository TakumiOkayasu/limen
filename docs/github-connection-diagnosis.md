# GitHub接続遅延 ルーター調査用レポート

## 症状

ブラウザでGitHub（`github.com`）アクセス時、一度切断状態になり自動復帰で表示される。SSH(port 22)は正常。

## 宛先

| 項目 | 値 |
|------|-----|
| ホスト | `github.com` |
| IPv4 | `20.27.177.113`（Azure Japan） |
| IPv6 AAAA | なし（GitHub未提供） |

## クライアント環境

| 項目 | 値 |
|------|-----|
| IF | イーサネット 2 |
| IPv4 | `192.168.1.116/24`（DHCP） |
| IPv6 | `2404:7a82:4d02:4101:973a:6094:ec2d:6358` |
| GW | `192.168.1.1` |
| DNS | `1.1.1.1`, `1.0.0.1`（DHCP配布） |
| MTU | 1500 |

## 接続テスト結果

| テスト | 結果 |
|--------|------|
| DNS解決 | ✅ 17ms |
| SSH (port 22) | ✅ 正常 |
| HTTP TCP接続 (port 80) | ⚠️ 1.79秒（遅い） |
| HTTPS TLS (port 443) | ❌ 15秒タイムアウト |
| ping (ICMP) | ❌ 全タイムアウト |
| ping 1472B DF=1 | ❌ 断片化必要エラー |
| ping 1400B | ❌ タイムアウト |
| ping 1200B | ❌ タイムアウト |

## traceroute (20.27.177.113)

| hop | 結果 |
|-----|------|
| 1 | `192.168.1.1` — 1ms ✅ |
| 2〜15 | 全ホップ `*`（タイムアウト） |

## 分析

1. **ICMPが全滅** — ルーターまたはISP側でICMPをブロック/優先度低下している可能性
2. **port 22は通るが port 443が極端に遅い** — ポート別のQoS/DPI/フィルタリングの疑い
3. **tracerouteがhop 2以降全滅** — ルーターのWAN側でICMP TTL exceededを返していない
4. **MTUテストも全滅（ICMPブロック由来）** — Path MTU Discoveryが機能していない可能性
5. **PMTUD失敗がTLSハンドシェイク失敗の直接原因の可能性大**

## ルーター側 確認推奨事項

1. **ICMP許可設定** — 特にType 3（Destination Unreachable）/ Code 4（Fragmentation Needed）
2. **port 443へのDPI/パケットインスペクション** の有無
3. **WAN側MTU** — PPPoE使用時は1454以下が必要
4. **MSS Clamping** — `iptables -t mangle` 等でTCP MSS調整が設定されているか
5. **conntrack / NATテーブル** — セッション数上限に達していないか
6. **他のサイトでも同様の事例が発生していないか**

---

## 原因

**MSS-CLAMP policy routeがeth2（LAN側）に未適用だった。**

MAP-Eトンネルはカプセル化によりMTUが小さくなる（1460以下）。MSS Clampingはトンネルインターフェース（mape）にのみ適用されていたが、LAN側（eth2）に適用されていなかったため、LANクライアントからのTCP SYNパケットにMSS調整が行われなかった。

結果として:
- 大きなTLSハンドシェイクパケットがトンネルのMTUを超過
- PMTUD（Path MTU Discovery）がICMPブロック環境で機能せず
- TLSハンドシェイクがタイムアウト（HTTPS接続失敗）
- SSH（port 22）は小パケットのため影響なし

## 対処

**恒久対応**（commit/save済み）:

```bash
[VyOS] configure
[VyOS] set policy route MSS-CLAMP interface eth2
[VyOS] commit
[VyOS] save
```

これによりeth2から入るTCP SYNパケットのMSSがトンネルMTUに合わせて自動調整される。

## 解決確認

| テスト | 環境 | 結果 |
|--------|------|------|
| `curl -I https://github.com` | Mac | ✅ 200 OK |
| `curl -I --ssl-no-revoke https://github.com` | Windows | ✅ 200 OK |

## 残存事項

- **Windows schannel 証明書失効チェックエラー**: Windows標準のschannel（`curl`デフォルト）で証明書失効チェック（OCSP/CRL）がエラーになる場合がある。`--ssl-no-revoke`で回避可能。これはルーター側の問題ではなく、Windows OS側のTLS実装に起因する。

# PiKVM トラブルシューティング

---

## 接続問題

### Web UIにアクセスできない

**症状**: https://pikvm.local にアクセスできない

**診断**:
```bash
[Mac] ping pikvm.local
[PiKVM] systemctl status kvmd
[PiKVM] journalctl -u kvmd -f
```

**対処**:

| 原因 | 対処 |
|------|------|
| ネットワーク未接続 | LANケーブル確認 |
| kvmdサービス停止 | `systemctl restart kvmd` |
| IPアドレス不明 | ルーターDHCPリース確認 |

---

### SSHに接続できない

**診断**:
```bash
[Mac] ssh -v root@pikvm.local
```

**対処**:

| 原因 | 対処 |
|------|------|
| sshdサービス停止 | Web UIからTerminalでアクセス、`systemctl restart sshd` |
| 公開鍵不一致 | `ssh-keygen -R pikvm.local` で古い鍵を削除 |
| ファイアウォール | PiKVMはデフォルトでFWなし、ネットワーク機器を確認 |

---

## 映像問題

### HDMI映像が表示されない

**診断**:
```bash
[PiKVM] journalctl -u kvmd -f
[PiKVM] cat /sys/class/video4linux/video0/name
```

**対処**:

| 原因 | 対処 |
|------|------|
| ケーブル接続不良 | HDMIケーブル挿し直し |
| VyOS出力なし | VyOS側でコンソール出力確認 |
| キャプチャデバイス不認識 | `reboot` |

---

### 映像が乱れる/ラグがある

**対処**:
1. Web UI → Settings → Video → Quality/FPS調整
2. H.264を有効化 (対応デバイスのみ)
3. ネットワーク帯域確認

---

## キーボード/マウス問題

### 入力が効かない

**診断**:
```bash
[PiKVM] ls -l /dev/hidg*
[PiKVM] journalctl -u kvmd | grep -i hid
```

**対処**:

| 原因 | 対処 |
|------|------|
| USBケーブル未接続 | OTGポート確認 |
| HIDデバイス未認識 | `reboot` |
| VyOS側USB無効 | VyOS BIOSでUSB有効化 |

---

## ストレージ問題

### ディスク容量不足

**診断**:
```bash
[PiKVM] df -h
```

**対処**:
```bash
[PiKVM] rw
[PiKVM] journalctl --vacuum-size=100M
[PiKVM] pacman -Sc
[PiKVM] ro
```

---

### read-only filesystem エラー

**原因**: PiKVMはデフォルトでread-only

**対処**:
```bash
[PiKVM] rw        # 書き込み可能に
# 作業実行
[PiKVM] ro        # 読み取り専用に戻す
```

---

## サービス問題

### kvmd が起動しない

**診断**:
```bash
[PiKVM] systemctl status kvmd
[PiKVM] journalctl -u kvmd --no-pager -n 50
```

**対処**:
```bash
[PiKVM] rw
[PiKVM] systemctl restart kvmd
[PiKVM] ro
```

設定ファイル破損の場合:
```bash
[PiKVM] rw
[PiKVM] cp /etc/kvmd/override.yaml /etc/kvmd/override.yaml.bak
[PiKVM] rm /etc/kvmd/override.yaml
[PiKVM] systemctl restart kvmd
[PiKVM] ro
```

---

## ネットワーク問題

### 固定IPに変更後接続できない

**対処**:
1. HDMIモニター直結でコンソールアクセス
2. `/etc/systemd/network/eth0.network` 修正
3. `systemctl restart systemd-networkd`

---

### mDNS (pikvm.local) で名前解決できない

**診断**:
```bash
[Mac] dns-sd -B _http._tcp
```

**対処**:

| 原因 | 対処 |
|------|------|
| avahi停止 | `systemctl restart avahi-daemon` |
| ルーターがmDNSブロック | IPアドレス直接指定 |

---

## 更新問題

### pacman -Syu 失敗

**対処**:
```bash
[PiKVM] rw
[PiKVM] pacman -Sy archlinux-keyring
[PiKVM] pacman -Syu
[PiKVM] ro
```

---

## ログ収集

問題報告時に以下を取得:

```bash
[PiKVM] journalctl -u kvmd --no-pager -n 100 > /tmp/kvmd.log
[PiKVM] dmesg > /tmp/dmesg.log
[PiKVM] cat /etc/kvmd/override.yaml > /tmp/override.yaml
[Mac] scp root@pikvm.local:/tmp/*.log ./
```

---

## 参考リンク

- [PiKVM FAQ](https://docs.pikvm.org/faq/)
- [PiKVM Discord](https://discord.gg/bpmXfz5)

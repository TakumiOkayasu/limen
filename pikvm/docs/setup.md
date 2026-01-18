# PiKVM セットアップ手順

VyOS自作ルーター管理用のPiKVM初期セットアップ。

---

## 前提条件

- Raspberry PiにPiKVM OSがインストール済み
- 有線LAN接続可能
- Mac側からSSHアクセス可能

---

## Phase 1: 初期アクセス

### 1-1: デフォルト認証情報

| サービス | ユーザー | パスワード |
| -------- | -------- | ---------- |
| SSH      | root     | root       |
| Web UI   | admin    | admin      |

### 1-2: IPアドレス確認

PiKVMはDHCPで自動取得。ルーターの管理画面またはmDNSで確認:

```bash
[Mac] ping pikvm.local
[Mac] ssh root@pikvm.local
```

---

## Phase 2: 初期設定

### 2-1: 読み取り専用モード解除

PiKVMはデフォルトで/がread-only。設定変更時は解除が必要:

```bash
[PiKVM] rw
```

設定完了後は再度read-onlyに戻す:

```bash
[PiKVM] ro
```

### 2-2: パスワード変更

```bash
[PiKVM] rw
[PiKVM] passwd root
[PiKVM] kvmd-htpasswd set admin
[PiKVM] ro
```

### 2-3: SSH公開鍵認証設定

```bash
[Mac] ssh-copy-id -i ~/.ssh/id_ed25519.pub root@pikvm.local
```

パスワード認証無効化:

```bash
[PiKVM] rw
[PiKVM] nano /etc/ssh/sshd_config
```

以下を変更:

```text
PasswordAuthentication no
```

```bash
[PiKVM] systemctl restart sshd
[PiKVM] ro
```

### 2-4: タイムゾーン設定

```bash
[PiKVM] rw
[PiKVM] timedatectl set-timezone Asia/Tokyo
[PiKVM] ro
```

---

## Phase 3: ネットワーク設定

### 3-1: 固定IPアドレス設定 (オプション)

DHCPで問題なければスキップ可能。固定IPにする場合:

```bash
[PiKVM] rw
[PiKVM] nano /etc/systemd/network/eth0.network
```

以下のように編集:

```ini
[Match]
Name=eth0

[Network]
Address=192.168.1.100/24
Gateway=192.168.1.1
DNS=192.168.1.1
```

```bash
[PiKVM] systemctl restart systemd-networkd
[PiKVM] ro
```

---

## Phase 4: VyOS連携設定

### 4-1: HDMI接続確認

1. PiKVMのHDMI入力をVyOSのHDMI出力に接続
2. Web UI (`https://pikvm.local`) にアクセス
3. VyOSの画面が表示されることを確認

### 4-2: USB経由シリアルコンソール設定

PiKVMのUSB OTGポートをVyOSのUSBポートに接続。

VyOS側でシリアルコンソールを有効化:

```bash
[VyOS] configure
[VyOS] set system console device ttyUSB0 speed 115200
[VyOS] commit
[VyOS] save
```

PiKVM Web UIで「Terminal」→「/dev/ttyUSB0」を選択してアクセス確認。

---

## Phase 5: 運用設定

### 5-1: Webインターフェース設定

Web UI (`https://pikvm.local`) で以下を設定:

- **System** → **Fan**: ファン速度調整
- **System** → **IPMI**: IPMI over LAN有効化 (オプション)
- **GPIO** → **Drivers**: ATXコントロール設定 (電源制御用、オプション)

### 5-2: 自動アップデート無効化 (推奨)

安定性優先のため、自動更新を無効化:

```bash
[PiKVM] rw
[PiKVM] systemctl disable kvmd-update.timer
[PiKVM] ro
```

手動更新:

```bash
[PiKVM] rw
[PiKVM] pacman -Syu
[PiKVM] ro
[PiKVM] reboot
```

---

## Phase 6: バックアップ

### 6-1: 設定ファイルのバックアップ

```bash
[Mac] mkdir -p pikvm/config/backup
[Mac] scp root@pikvm.local:/etc/kvmd/override.yaml pikvm/config/backup/
[Mac] scp root@pikvm.local:/etc/systemd/network/eth0.network pikvm/config/backup/
```

### 6-2: SDカードイメージバックアップ (推奨)

```bash
[Mac] ssh root@pikvm.local 'dd if=/dev/mmcblk0 bs=4M status=progress' | gzip > pikvm-backup-$(date +%Y%m%d).img.gz
```

**注意**: 数GB〜数十GBのデータ転送が発生。時間がかかる。

---

## 検証

以下を確認:

- [ ] Web UIにアクセス可能
- [ ] SSH公開鍵認証でログイン可能
- [ ] VyOSの画面がHDMI経由で表示される
- [ ] シリアルコンソールでVyOSにアクセス可能
- [ ] タイムゾーンがAsia/Tokyo

---

## トラブルシューティング

### Web UIにアクセスできない

```bash
[PiKVM] systemctl status kvmd
[PiKVM] journalctl -u kvmd -f
```

### シリアルコンソールが認識されない

VyOS側のUSBデバイス確認:

```bash
[VyOS] ls -l /dev/ttyUSB*
[VyOS] dmesg | grep ttyUSB
```

PiKVM側の確認:

```bash
[PiKVM] ls -l /dev/ttyUSB*
```

---

## Appendix A: Bluetoothキーボード/マウス設定

Pi Zero WでPiKVM本体をローカル操作する場合、USB OTGポートはVyOSへのHID用に使用されるため、Bluetooth接続が現実的。

### A-1: 対応モデル

| モデル         | Bluetooth | 備考             |
| -------------- | --------- | ---------------- |
| Pi Zero W      | 内蔵 ✅    | BCM43438         |
| Pi Zero 2 W    | 内蔵 ✅    | BCM43436         |
| Pi 3/4/5       | 内蔵 ✅    |                  |
| Pi Zero (無印) | ❌         | USBアダプタ必要 |

### A-2: パッケージインストール

```bash
[PiKVM] rw
[PiKVM] pacman -Sy bluez bluez-utils
[PiKVM] systemctl enable --now bluetooth
```

### A-3: デバイスペアリング

```bash
[PiKVM] bluetoothctl
```

bluetoothctl内で以下を実行:

```text
power on
agent on
default-agent
scan on
```

キーボード/マウスをペアリングモードにし、MACアドレスが表示されたら:

```text
pair XX:XX:XX:XX:XX:XX
trust XX:XX:XX:XX:XX:XX
connect XX:XX:XX:XX:XX:XX
```

複数デバイスの場合は `pair`/`trust`/`connect` を各デバイスで繰り返す。完了後:

```text
exit
```

### A-4: 自動接続設定

```bash
[PiKVM] sed -i 's/#AutoEnable=false/AutoEnable=true/' /etc/bluetooth/main.conf
[PiKVM] ro
```

### A-5: 確認

```bash
[PiKVM] bluetoothctl devices
[PiKVM] bluetoothctl info XX:XX:XX:XX:XX:XX
```

| 状態      | 期待値 |
| --------- | ------ |
| Connected | yes    |
| Trusted   | yes    |
| Paired    | yes    |

---

## 参考リンク

- [PiKVM公式ドキュメント](https://docs.pikvm.org/)
- [PiKVM GitHub](https://github.com/pikvm/pikvm)

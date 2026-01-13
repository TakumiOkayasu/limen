# PiKVM セットアップ手順

Raspberry Pi Zero W/WH を使用したリモートKVM環境の構築手順。

---

## 概要

PiKVMを導入することで、以下が遠隔から可能になる:

- BIOS/UEFI画面の操作
- GRUBメニューの選択
- OSが起動しない場合の復旧作業
- コンソールログインと操作
- 電源ON/OFF/リセット (ATX制御ボード追加時)

**ユースケース**:
- カーネル更新後にGRUBで旧カーネルを選択して復旧
- 起動しなくなったVyOSをリモートから復旧
- BIOSの設定変更

---

## 必要な機材

| 部品 | 用途 | 状態 | 備考 |
|------|------|------|------|
| Raspberry Pi Zero W/WH | PiKVM本体 | 所持済み | Pi Zero 2 Wでも可 |
| HDMIキャプチャ (USB) | 画面取得 | 購入済み | SensaBliss 2in1 (USB-A/USB-C両対応) |
| microSDカード (16GB以上) | PiKVMイメージ用 | 所持済み | 8GBでも可だが16GB推奨 |
| USB OTGアダプタ | キャプチャ接続用 | 所持済み | USB-A (メス) → microUSB (オス) |
| microUSBケーブル | HIDエミュレーション用 | 所持済み | データ通信対応のもの |
| USB電源 (5V 2A以上) | Pi用電源 | 所持済み | 安定した電源が必要 |
| HDMIケーブル | VyOS → キャプチャ接続 | 所持済み | - |
| USBハブ (セルフパワー推奨) | 複数USB機器接続 | 所持済み | Pi Zero Wでは必須 |

---

## Pi Zero W の制限事項

| 項目 | Pi Zero W/WH | Pi 4 (参考) |
|------|--------------|-------------|
| データ用USBポート | 1つのみ (microUSB) | 4つ (USB-A) |
| 解像度 | 720p推奨 | 1080p対応 |
| フレームレート | 10-15fps | 30fps+ |
| CPU性能 | シングルコア 1GHz | クアッドコア 1.5GHz |
| RAM | 512MB | 2-8GB |

**重要**: Pi Zero Wはデータ用USBポートが1つしかないため、HDMIキャプチャとHIDエミュレーション (キーボード/マウス) を同時に接続するにはUSBハブが必須。

---

## 物理接続図

```
[VyOS サーバー (HP ProDesk 600 G4)]
    │
    ├── HDMI出力 ───→ [HDMIキャプチャ] ─┐
    │                                    │
    │                                    ▼
    │                              [USBハブ] ───→ [OTGアダプタ] ───→ [Pi Zero W (DATA)]
    │                                    │
    │                                    │ (HID: キーボード/マウスエミュレーション)
    │                                    │
    └── USB-Aポート ←─────────────────────┘

[Pi Zero W]
    ├── 左側 microUSB (PWR) ←── [5V USB電源]
    └── 右側 microUSB (DATA) ←── [USBハブ] ←── [HDMIキャプチャ + HIDケーブル]
```

### Pi Zero W のポート配置

```
        ┌─────────────────────────────────────┐
        │  [mini HDMI]  [DATA]  [PWR]         │
        │      ▲          ▲       ▲           │
        │      │          │       │           │
        │   未使用    USBハブ   電源          │
        │            接続      接続           │
        └─────────────────────────────────────┘
```

---

## セットアップ手順

### 手順1: PiKVMイメージのダウンロード

**[Mac]**

```bash
# 作業ディレクトリを作成
mkdir -p ~/pikvm-setup && cd ~/pikvm-setup

# 所持しているPi Zeroのモデルを確認してダウンロード
# Pi Zero W の場合:
curl -L -o pikvm-image.img.xz https://files.pikvm.org/images/v2-hdmi-zerow-latest.img.xz

# Pi Zero 2 W の場合:
# curl -L -o pikvm-image.img.xz https://files.pikvm.org/images/v2-hdmi-zero2w-latest.img.xz

# ダウンロード完了を確認
ls -lh pikvm-image.img.xz
# 約400-500MB程度
```

**モデルの見分け方**:
- Pi Zero W: 基板に「Raspberry Pi Zero W」と印刷
- Pi Zero 2 W: 基板に「Raspberry Pi Zero 2 W」と印刷、CPUが大きい

---

### 手順2: イメージの展開

**[Mac]**

```bash
cd ~/pikvm-setup

# xzファイルを展開 (数分かかる)
xz -d pikvm-image.img.xz

# 展開後のファイルを確認
ls -lh pikvm-image.img
# 約2-3GB程度
```

---

### 手順3: microSDカードの準備

**[Mac]**

```bash
# microSDカードをMacに挿入

# 接続されているディスクを確認
diskutil list

# 出力例:
# /dev/disk4 (external, physical):
#    #:                       TYPE NAME                    SIZE       IDENTIFIER
#    0:     FDisk_partition_scheme                        *15.9 GB    disk4
#    1:             Windows_FAT_32 NO NAME                 15.9 GB    disk4s1

# microSDカードのデバイス名をメモ (例: /dev/disk4)
# サイズで判断する (16GBなら15.9GB程度と表示される)
```

**注意**: 間違ったディスクを選択すると、そのディスクのデータが全て消去される。必ずサイズで確認すること。

---

### 手順4: イメージの書き込み

**[Mac]**

```bash
cd ~/pikvm-setup

# SDカードをアンマウント (例: /dev/disk4)
# 実際のデバイス名に置き換えること
diskutil unmountDisk /dev/disk4

# イメージを書き込み (rdiskを使用すると高速)
# 実際のデバイス名に置き換えること
sudo dd if=pikvm-image.img of=/dev/rdisk4 bs=1m status=progress

# 完了まで5-15分程度かかる
# 書き込み完了後、SDカードを取り出し
diskutil eject /dev/disk4
```

---

### 手順5: Wi-Fi設定 (初回起動前)

SDカードを再度Macに挿入し、Wi-Fi設定を書き込む。

**[Mac]**

```bash
# bootパーティションが自動マウントされるのを待つ (数秒)

# マウントされたか確認
ls /Volumes/boot
# config.txt などが見えればOK

# Wi-Fi設定ファイルを作成
cat > /Volumes/boot/pikvm.txt << 'EOF'
WIFI_ESSID="your-wifi-ssid"
WIFI_PASSWD="your-wifi-password"
EOF

# 設定内容を確認
cat /Volumes/boot/pikvm.txt

# SDカードを取り出し
diskutil eject /Volumes/boot
```

**注意**:
- `your-wifi-ssid` と `your-wifi-password` は実際の値に置き換える
- SSIDやパスワードにスペースや特殊文字が含まれる場合はそのまま記載してOK
- 2.4GHz帯のWi-Fiを使用すること (Pi Zero Wは5GHz非対応)

---

### 手順6: ハードウェアの接続

以下の順番で接続する:

1. **microSDカードをPi Zero Wに挿入**

2. **USBハブをPi Zero W (DATA) に接続**
   - OTGアダプタを使用: USBハブ (USB-A) → OTGアダプタ → Pi Zero W (microUSB DATA)

3. **HDMIキャプチャをUSBハブに接続**
   - HDMIキャプチャ (USB-A) → USBハブ

4. **HIDケーブルをUSBハブに接続**
   - microUSBケーブル → USBハブ
   - もう一端は後でVyOSサーバーに接続

5. **HDMIケーブルを接続**
   - VyOSサーバー (HDMI出力) → HDMIキャプチャ (HDMI入力)

6. **HIDケーブルをVyOSサーバーに接続**
   - microUSBケーブルのもう一端 → VyOSサーバー (USB-Aポート)

7. **電源を接続 (最後に)**
   - USB電源 → Pi Zero W (microUSB PWR)

---

### 手順7: 起動と接続確認

**[Mac]**

```bash
# Pi Zero Wの起動を待つ (初回は1-2分かかる)
sleep 120

# PiKVMを探す (mDNS)
ping -c 3 pikvm.local

# 応答があればOK
# PING pikvm.local (192.168.1.xxx): 56 data bytes
# 64 bytes from 192.168.1.xxx: icmp_seq=0 ttl=64 time=xx.xxx ms

# 応答がない場合、ルーターのDHCPリース一覧でIPアドレスを確認
```

**mDNSが動作しない場合の代替手段**:

```bash
# ルーターの管理画面でDHCPリース一覧を確認
# または、ネットワークスキャン
nmap -sn 192.168.1.0/24 | grep -B2 "Raspberry"
```

---

### 手順8: WebUIにアクセス

ブラウザで以下にアクセス:

```
https://pikvm.local
```

または:

```
https://<PiKVMのIPアドレス>
```

**証明書の警告**:
- 自己署名証明書のため警告が表示される
- 「詳細設定」→「pikvm.localにアクセスする」をクリック

**デフォルト認証情報**:
| 項目 | 値 |
|------|-----|
| ユーザー名 | admin |
| パスワード | admin |

---

### 手順9: 初期設定

#### 9-1: パスワード変更

**[PiKVM WebUI]**

1. 右上のメニュー → 「Settings」
2. 「Users」セクション
3. adminユーザーのパスワードを変更

または、SSH経由で変更:

**[Mac]**

```bash
# PiKVMにSSH接続 (デフォルトパスワード: root)
ssh root@pikvm.local

# パスワード変更
kvmd-htpasswd set admin

# 新しいパスワードを入力
```

#### 9-2: タイムゾーン設定

**[PiKVM SSH]**

```bash
# タイムゾーンを日本に設定
timedatectl set-timezone Asia/Tokyo

# 確認
timedatectl
```

#### 9-3: 画面解像度の調整

Pi Zero Wでは720p以下を推奨。

**[PiKVM WebUI]**

1. メイン画面で「System」メニュー
2. 「Video」設定
3. 「Quality」を下げる (50-70%程度)
4. 「Desired FPS」を下げる (10-15程度)

---

### 手順10: 動作確認

**[PiKVM WebUI]**

1. メイン画面にVyOSサーバーの画面が表示されることを確認
2. キーボード入力が反映されることを確認
   - 画面をクリックしてフォーカス
   - キーを押してVyOSに入力されるか確認
3. マウス操作が反映されることを確認 (BIOS画面等で有用)

**確認項目チェックリスト**:

| 項目 | 確認方法 | 期待結果 |
|------|---------|---------|
| 画面表示 | WebUIを開く | VyOSの画面が見える |
| キーボード | 文字を入力 | VyOSに文字が入力される |
| 特殊キー | Ctrl+Alt+Delete等 | 正しく送信される |
| 再起動後 | VyOSを再起動 | GRUBメニューが操作できる |

---

## VyOSサーバー再起動時の操作

PiKVMの主な用途: GRUBメニューでのカーネル選択

**[PiKVM WebUI]**

1. VyOSサーバーを再起動
2. PiKVM WebUIでGRUBメニューが表示されるのを待つ
3. 矢印キーでカーネルを選択
4. Enterキーで起動

**特殊キーの送信**:

WebUI右側のツールバーから送信可能:
- Ctrl+Alt+Delete
- F1-F12キー
- その他の特殊キーコンビネーション

---

## トラブルシューティング

### 画面が映らない

**[PiKVM SSH]**

```bash
ssh root@pikvm.local

# キャプチャデバイスの確認
lsusb
# "Macrosilicon" や "534d:2109" が見えればOK

# ビデオデバイスの確認
ls -la /dev/video*
# /dev/video0 が存在すればOK

# キャプチャの状態確認
v4l2-ctl --list-devices
```

**原因と対策**:

| 症状 | 原因 | 対策 |
|------|------|------|
| lsusbにキャプチャが表示されない | USB接続不良 | ケーブル/ハブを確認 |
| /dev/video0がない | ドライバ未ロード | Pi再起動 |
| 画面が真っ黒 | HDMIケーブル不良 | ケーブル交換 |
| 画面が乱れる | 解像度不一致 | VyOS側の解像度を下げる |

---

### キーボード/マウスが効かない

**[PiKVM SSH]**

```bash
ssh root@pikvm.local

# HIDデバイスの確認
ls -la /dev/hidg*
# /dev/hidg0, /dev/hidg1 が存在すればOK

# USBガジェットモードの確認
dmesg | grep -i gadget

# kvmdサービスの状態
systemctl status kvmd
```

**原因と対策**:

| 症状 | 原因 | 対策 |
|------|------|------|
| /dev/hidg*がない | OTGモード未設定 | config.txt確認、Pi再起動 |
| VyOSが反応しない | USBケーブル不良 | データ通信対応ケーブルに交換 |
| 一部キーが効かない | キーマップ問題 | WebUIの特殊キーメニューを使用 |

---

### ネットワークに接続できない

**原因と対策**:

| 症状 | 原因 | 対策 |
|------|------|------|
| pikvm.localが見つからない | mDNS問題 | IPアドレスで直接アクセス |
| IPアドレスが取得できない | Wi-Fi設定ミス | pikvm.txt確認、SSID/パスワード確認 |
| 5GHz Wi-Fiに接続できない | Pi Zero W非対応 | 2.4GHz帯を使用 |

**Wi-Fi設定の確認 (SDカードをMacに挿入)**:

```bash
cat /Volumes/boot/pikvm.txt
```

---

### 動作が遅い/カクカクする

Pi Zero Wの性能限界による。

**対策**:

1. **WebUIで画質を下げる**
   - Quality: 50%以下
   - FPS: 10以下

2. **解像度を下げる**
   - VyOSサーバー側でコンソール解像度を720pに設定

3. **不要なサービスを停止**
   ```bash
   ssh root@pikvm.local
   systemctl stop kvmd-vnc  # VNCが不要なら停止
   ```

---

## 将来の拡張

### ATX制御ボードの追加

電源ON/OFF/リセットをリモートから操作可能にする。

**必要な部品**:
- PiKVM ATX制御ボード (またはリレーモジュール)
- マザーボードの電源/リセットピンへの接続ケーブル

### Pi 4へのアップグレード

より快適な操作が必要な場合:

| 項目 | Pi Zero W | Pi 4 |
|------|-----------|------|
| 画質 | 720p / 10fps | 1080p / 30fps |
| 遅延 | 0.5-1秒 | 0.1-0.2秒 |
| CSI-2キャプチャ | 非対応 | 対応 (低遅延) |

---

## 参考リンク

- [PiKVM公式ドキュメント](https://docs.pikvm.org/)
- [PiKVM GitHub](https://github.com/pikvm/pikvm)
- [Pi Zero W用イメージ](https://files.pikvm.org/images/)
- [PiKVM Discord](https://discord.gg/bpmXfz5) - コミュニティサポート

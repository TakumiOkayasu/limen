# VyOS VM カーネルテスト手順書

CIでビルドしたカスタムカーネルをVyOS VMでテストする手順。

## 前提条件

- UTMでVyOS VMが起動している
- GitHub ActionsでビルドしたArtifacts (vyos-kernel-packages, r8126-signed-module) をダウンロード済み

## 手順

### 1. VM初期設定 (再起動しても永続)

**[VyOS VM コンソール]**

```bash
# VyOS設定モードでSSHとインターフェースを設定
configure

# SSH有効化
set service ssh port 22

# eth0を有効化 (DHCP)
set interfaces ethernet eth0 address dhcp

# パスワード認証を有効化 (テスト用)
set service ssh disable-password-authentication

commit
save
exit
```

設定後、SSHサービスとeth0が自動的に有効になる。

### 2. ファイル転送 (永続ディレクトリへ)

**[Mac]**

```bash
# VMのIPアドレスを確認 (例: 192.168.64.10)
arp -a | grep bridge

# 永続ディレクトリ (/config) に転送
scp -r vyos-kernel-packages r8126-signed-module vyos@192.168.64.10:/config/
```

`/config` はVyOSの永続ストレージで、再起動後も保持される。

### 3. カーネルパッケージをインストール

**[VyOS VM]**

```bash
cd /config/vyos-kernel-packages
sudo dpkg -i linux-*.deb
```

GRUBエラー (`failed to get canonical path of 'overlay'`) は無視してOK。

### 4. カーネルを置き換えて起動

**[VyOS VM]**

```bash
# バックアップ
sudo cp /boot/vmlinuz /boot/vmlinuz.bak
sudo cp /boot/initrd.img /boot/initrd.img.bak

# 新カーネルで置き換え
sudo cp /boot/vmlinuz-6.6.117-vyos /boot/vmlinuz
sudo cp /boot/initrd.img-6.6.117-vyos /boot/initrd.img

# 再起動
sudo reboot
```

### 5. 検証

**[VyOS VM]**

```bash
# カーネルバージョン確認
uname -r
# 期待値: 6.6.117-vyos

# nftablesが動作するか (最重要)
sudo nft list tables

# VyOS設定システムが動作するか
configure
commit
exit

# モジュール署名確認
lsmod | grep nf_tables
```

## 成功基準

1. `uname -r` が `6.6.117-vyos` を返す
2. `sudo nft list tables` がテーブル一覧を表示する (エラーなし)
3. `configure` → `commit` が成功する

## トラブルシューティング

### nft: Unable to initialize Netlink socket: Protocol not supported

**原因**: nf_tablesモジュールがロードできない (署名不一致)

**確認方法**:
```bash
sudo modprobe nf_tables 2>&1
# "Key was rejected by service" → 署名鍵の不一致

dmesg | grep -i "key\|certificate" | head -10
# カーネルに組み込まれた鍵とモジュールの署名鍵を比較

modinfo /lib/modules/$(uname -r)/kernel/net/netfilter/nf_tables.ko | grep sig_key
```

**原因**: 古いカーネルから起動している

```bash
cat /proc/cmdline
# BOOT_IMAGE が /boot/vmlinuz を指しているか確認
```

### SSH接続できない

```bash
# VM側でサービス確認
sudo systemctl status ssh

# インターフェースがUPか確認
ip a show eth0
sudo ip link set eth0 up
```

### 元のカーネルに戻す

```bash
sudo cp /boot/vmlinuz.bak /boot/vmlinuz
sudo cp /boot/initrd.img.bak /boot/initrd.img
sudo reboot
```

## 本番環境への適用

### VMと本番の違い

| 項目 | VM | 本番VyOS |
|------|-----|----------|
| ブート方式 | UTM/QEMU | 実機 EFI |
| ストレージ | 仮想ディスク | NVMe/SATA |
| NIC | virtio/e1000 | Intel X540-T2, オンボード |
| 復旧手段 | スナップショット | 物理コンソール |

### 適用前の確認事項

**[VyOS VM]** で本番ハードウェア用ドライバの存在を確認:

```bash
# Intel 10GbE (X540-T2) ドライバ
modinfo ixgbe 2>/dev/null | head -3

# initrdに必要なドライバが含まれているか
lsinitrd /boot/initrd.img-6.6.117-vyos 2>/dev/null | grep -E "ixgbe|nvme|ahci" || \
  zcat /boot/initrd.img-6.6.117-vyos | cpio -t 2>/dev/null | grep -E "ixgbe|nvme|ahci"
```

---

### パターン A: 安全重視 (推奨)

物理コンソール + USBリカバリメディアを用意してから適用。

**準備**:
1. 本番VyOSにモニター・キーボードを接続
2. VyOS ISOをUSBに書き込み (リカバリ用)
3. 現在の設定をバックアップ: `save /config/backup-$(date +%Y%m%d).boot`

**適用手順**:

```bash
# 1. ファイル転送
scp -r vyos-kernel-packages vyos@<本番IP>:/config/

# 2. 本番VyOSにSSH接続
ssh vyos@<本番IP>

# 3. バックアップ
sudo cp /boot/vmlinuz /boot/vmlinuz.bak
sudo cp /boot/initrd.img /boot/initrd.img.bak

# 4. カーネルインストール
cd /config/vyos-kernel-packages
sudo dpkg -i linux-*.deb

# 5. カーネル置き換え
sudo cp /boot/vmlinuz-6.6.117-vyos /boot/vmlinuz
sudo cp /boot/initrd.img-6.6.117-vyos /boot/initrd.img

# 6. 再起動 (物理コンソールで監視)
sudo reboot
```

**失敗時の復旧**:
- 物理コンソールでGRUBメニューから旧カーネルを選択
- または、USBから起動してバックアップを復元

---

### パターン B: リモート作業 (上級者向け)

物理アクセスなしでリモートから適用。失敗時は現地対応が必要。

**前提条件**:
- IPMI/iLO/iDRAC等のリモートコンソールがある
- または、失敗時に現地へ行ける

**適用手順**:

```bash
# 1. 現在の状態を記録
ssh vyos@<本番IP> "show version; show configuration commands" > pre-upgrade-state.txt

# 2. ファイル転送
scp -r vyos-kernel-packages vyos@<本番IP>:/config/

# 3. 本番で実行
ssh vyos@<本番IP> << 'EOF'
sudo cp /boot/vmlinuz /boot/vmlinuz.bak
sudo cp /boot/initrd.img /boot/initrd.img.bak
cd /config/vyos-kernel-packages
sudo dpkg -i linux-*.deb
sudo cp /boot/vmlinuz-6.6.117-vyos /boot/vmlinuz
sudo cp /boot/initrd.img-6.6.117-vyos /boot/initrd.img
sudo reboot
EOF

# 4. 再起動後の確認 (2-3分待つ)
sleep 180
ssh vyos@<本番IP> "uname -r; sudo nft list tables"
```

**失敗時**: 現地で物理コンソールからロールバック

---

### パターン C: 段階的適用 (最も安全)

新カーネルを別ブートエントリとして追加し、GRUBで選択可能にする。
既存のカーネルはそのまま残るため、失敗しても再起動で元に戻せる。

**メリット**:
- 失敗しても再起動でGRUBメニューから元のエントリを選択可能
- 本番環境を壊すリスクが最小限
- 物理コンソールがあれば確実に復旧できる

**デメリット**:
- GRUBメニューで手動選択が必要 (デフォルトは元のカーネル)
- 物理コンソールまたはPiKVM等のリモートコンソールが必須

**前提条件**:
- 物理コンソール (モニター + キーボード) またはPiKVM等でGRUB操作が可能

---

#### 手順1: ファイル転送

**[Mac]**

```bash
# 本番VyOSにカーネルパッケージを転送
scp -r vyos-kernel-packages vyos@192.168.1.1:/config/
```

---

#### 手順2: SSH接続してカーネルをインストール

**[Mac]**

```bash
ssh vyos@192.168.1.1
```

**[本番VyOS]**

```bash
# カーネルパッケージをインストール
cd /config/vyos-kernel-packages
sudo dpkg -i linux-*.deb

# GRUBエラーは無視してOK:
# "dpkg: error processing package linux-image-6.6.117-vyos"
# "failed to get canonical path of 'overlay'"
# カーネルファイル自体は正常にインストールされている
```

---

#### 手順3: 現在のブートパラメータを確認

**[本番VyOS]**

```bash
# 現在のvyos-unionパスを確認 (この値をGRUBエントリで使用する)
cat /proc/cmdline
```

出力例:
```
BOOT_IMAGE=/boot/2026.01.06-0022-rolling/vmlinuz boot=live rootdelay=5 noautologin net.ifnames=0 biosdevname=0 vyos-union=/boot/2026.01.06-0022-rolling console=tty0
```

**重要**: `vyos-union=/boot/2026.01.06-0022-rolling` の部分をメモする。
この値は環境によって異なる (バージョン番号部分)。

---

#### 手順4: GRUBエントリを作成

**[本番VyOS]**

```bash
# 新カーネルとinitrdが存在することを確認
ls -la /boot/vmlinuz-6.6.117-vyos /boot/initrd.img-6.6.117-vyos

# vyos-unionパスを自動取得
VYOS_UNION=$(cat /proc/cmdline | grep -o 'vyos-union=/boot/[^ ]*' | cut -d= -f2)
echo "取得したパス: ${VYOS_UNION}"
# 出力例: 取得したパス: /boot/2026.01.06-0022-rolling

# パスが正しく取得できたことを確認してからGRUBエントリを作成
sudo tee /boot/grub/grub.cfg.d/vyos-versions/99-r8126-custom-kernel.cfg << EOF
menuentry "VyOS 6.6.117 Custom Kernel (r8126 support)" --id r8126-custom-kernel {
    linux /boot/vmlinuz-6.6.117-vyos boot=live rootdelay=5 noautologin net.ifnames=0 biosdevname=0 vyos-union=${VYOS_UNION} console=tty0
    initrd /boot/initrd.img-6.6.117-vyos
}
EOF

# 作成結果を確認 (vyos-union= に正しいパスが入っていることを確認)
cat /boot/grub/grub.cfg.d/vyos-versions/99-r8126-custom-kernel.cfg
```

---

#### 手順5: GRUBメニューの順番を確認

**[本番VyOS]**

```bash
# GRUBエントリのファイル一覧 (辞書順で読み込まれる)
ls -la /boot/grub/grub.cfg.d/vyos-versions/
```

出力例:
```
-rw-r--r-- 1 root root  XXX Jan XX XX:XX 2026.01.06-0022-rolling.cfg
-rw-r--r-- 1 root root  XXX Jan XX XX:XX 99-r8126-custom-kernel.cfg
```

`99-` で始まるファイルは最後に読み込まれるため、GRUBメニューの下の方に表示される。

**メニューの一番上に表示したい場合**:
```bash
sudo mv /boot/grub/grub.cfg.d/vyos-versions/99-r8126-custom-kernel.cfg \
        /boot/grub/grub.cfg.d/vyos-versions/01-r8126-custom-kernel.cfg
```

---

#### 手順6: 再起動してカスタムカーネルを選択

**[本番VyOS]**

```bash
sudo reboot
```

**[物理コンソール または PiKVM]**

1. 再起動後、GRUBメニューが表示される (5秒のタイムアウト)
2. 矢印キーで「VyOS 6.6.117 Custom Kernel (r8126 support)」を選択
3. Enterキーで起動

---

#### 手順7: 起動後の検証

**[本番VyOS]** (SSH または コンソール)

```bash
# カーネルバージョンを確認
uname -r
# 期待値: 6.6.117-vyos

# nftablesが動作するか確認 (最重要)
sudo nft list tables
# テーブル一覧が表示されればOK
# エラー "Protocol not supported" が出たら失敗

# VyOS設定システムが動作するか確認
configure
commit
exit
# "No configuration changes to commit" と表示されればOK

# ネットワークインターフェースの確認
ip a
# eth0, eth1, eth2 が認識されていることを確認

# r8126モジュールの確認 (将来用、現時点では未ロード)
modinfo r8126 2>/dev/null || echo "r8126 module not installed yet"
```

---

#### 手順8: 成功した場合 - デフォルト化

検証が成功したら、カスタムカーネルをデフォルトにする。

**[本番VyOS]**

```bash
# 現在のカーネルをバックアップ
sudo cp /boot/vmlinuz /boot/vmlinuz.original
sudo cp /boot/initrd.img /boot/initrd.img.original

# カスタムカーネルをデフォルトに設定
sudo cp /boot/vmlinuz-6.6.117-vyos /boot/vmlinuz
sudo cp /boot/initrd.img-6.6.117-vyos /boot/initrd.img

# GRUBエントリを削除 (元のエントリがカスタムカーネルを使うようになったため不要)
sudo rm /boot/grub/grub.cfg.d/vyos-versions/*-r8126-custom-kernel.cfg

# 再起動して確認
sudo reboot
```

---

#### 手順9: 失敗した場合 - ロールバック

カスタムカーネルで問題が発生した場合。

**方法A: SSH接続可能な場合**

```bash
# GRUBエントリを削除
sudo rm /boot/grub/grub.cfg.d/vyos-versions/*-r8126-custom-kernel.cfg
sudo reboot
```

**方法B: SSH不可、物理コンソールからGRUB選択**

1. 再起動
2. GRUBメニューで元のエントリ「2026.01.06-0022-rolling」を選択
3. 起動後、上記の方法Aを実行

**方法C: GRUBメニューも表示されない場合**

1. 電源長押しで強制再起動
2. 起動時にShiftキーを押し続けてGRUBメニューを表示
3. 元のエントリを選択

---

### ロールバック手順

どのパターンでも、以下で元に戻せる:

**SSH接続可能な場合**:
```bash
sudo cp /boot/vmlinuz.bak /boot/vmlinuz
sudo cp /boot/initrd.img.bak /boot/initrd.img
sudo reboot
```

**SSH不可 (物理コンソール)**:
1. 再起動してGRUBメニューを表示 (Shift押しながら起動)
2. 「e」キーでエントリ編集
3. `linux` 行を `/boot/vmlinuz.bak` に変更
4. Ctrl+X で起動
5. 起動後、上記のロールバックコマンドを実行

**完全に起動不可 (USBリカバリ)**:
1. VyOS ISOからUSBブート
2. `install image` ではなく `live` モードで起動
3. 本番ディスクをマウント: `sudo mount /dev/sda3 /mnt`
4. バックアップを復元:
   ```bash
   sudo cp /mnt/vmlinuz.bak /mnt/vmlinuz
   sudo cp /mnt/initrd.img.bak /mnt/initrd.img
   ```
5. アンマウントして再起動: `sudo umount /mnt && sudo reboot`

## 参考

- [work-log-2026-01-13.md](work-log-2026-01-13.md) - 署名問題の詳細
- [failure-log-2026-01-07-kernel-update.md](failure-log-2026-01-07-kernel-update.md) - MODULE_SIG_FORCE問題

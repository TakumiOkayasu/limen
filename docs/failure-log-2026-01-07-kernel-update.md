# 失敗記録: カーネルアップデートによるVyOS起動不能

**日付**: 2026-01-07
**影響**: VyOS起動不能、再インストール必要
**深刻度**: 高

---

## 概要

RTL8126 (5GbE) ドライバをロードするため、MODULE_SIG_FORCE=n でカーネルを再ビルドしてインストールしたところ、VyOSが起動不能になった。

---

## 経緯

### やりたかったこと

- RTL8126 (5GbE NIC) をVyOSで使用したい
- 標準カーネルは `CONFIG_MODULE_SIG_FORCE=y` で署名なしモジュールをロードできない
- カーネルを `MODULE_SIG_FORCE=n` で再ビルドしてドライバをロード可能にする

### 実行した手順

1. GitHub ActionsでVyOSカーネルをビルド (MODULE_SIG_FORCE=n を意図)
2. ビルドしたdebパッケージをVyOSにscp
3. `sudo dpkg -i linux-image-*.deb` でインストール
4. `sudo reboot` で再起動
5. **起動失敗** - conntrack等の基本モジュールがロードできずネットワーク不能

### 発生した問題

```
modprobe: ERROR: could not insert 'nf_conntrack': Key was rejected by service
eth0: A/D (Admin Down)
eth1: A/D (Admin Down)
eth2: A/D (Admin Down)
ssh.service: disabled
```

**結果**: MODULE_SIG_FORCE が依然として有効で、VyOSの基本機能(conntrack, ファイアウォール等)が動作せず、ネットワーク接続不能。

---

## 根本原因

1. **CIでのビルド設定が反映されていなかった**
   - `scripts/config --disable MODULE_SIG_FORCE` を追加したが、実際のカーネルでは `=y` のまま
   - ビルド後の検証を行わなかった

2. **カーネル署名の影響範囲を理解していなかった**
   - r8126.ko だけでなく、VyOSの全モジュール(conntrack, iptables等)も署名が必要
   - 署名なしカーネルでは基本機能が全滅する

---

## 反省点と教訓

### 1. 本番環境での直接テスト

| やったこと | やるべきだったこと |
|-----------|-------------------|
| 稼働中VyOSでカーネル入れ替え | VMで事前検証 |

**教訓**: カーネル変更は必ずテスト環境で検証してから本番適用

### 2. ビルド成果物の検証不足

| やったこと | やるべきだったこと |
|-----------|-------------------|
| debをそのままインストール | インストール前にconfig確認 |

**教訓**: 以下で検証してからインストール
```bash
dpkg -x linux-image-*.deb /tmp/extract
grep CONFIG_MODULE_SIG_FORCE /tmp/extract/boot/config-*
```

### 3. ロールバック計画の欠如

| やったこと | やるべきだったこと |
|-----------|-------------------|
| 計画なしで実行 | GRUBで旧カーネル起動を事前確認 |

**教訓**: 変更前に必ずロールバック手順を確認・テスト

### 4. バックアップの不足

| やったこと | やるべきだったこと |
|-----------|-------------------|
| 設定バックアップなし | 変更前に `show configuration commands > backup.txt` |

**教訓**: 大きな変更前は必ず設定をエクスポート

### 5. 並行作業による複雑化

| やったこと | やるべきだったこと |
|-----------|-------------------|
| カーネル変更とWXR設定を同時進行 | 1つずつ変更、各ステップで動作確認 |

**教訓**: 複数の変更を同時に行わない

### 6. CIパイプラインの検証不足

| やったこと | やるべきだったこと |
|-----------|-------------------|
| CIログを確認せずアーティファクト使用 | ビルドログでMODULE_SIG設定を確認 |

**教訓**: CIのアーティファクトにconfigファイルを含めて検証可能にする

---

## 安全な手順 (今後のカーネル更新時)

### Phase 1: 準備

```bash
# 1. 現在の設定をバックアップ
show configuration commands > /config/backup-$(date +%Y%m%d).txt

# 2. 現在のカーネルバージョンを記録
uname -r
ls /boot/vmlinuz-*

# 3. GRUBで旧カーネル起動できることを確認
# 再起動してGRUBメニューを表示、旧カーネルを選択して起動テスト
```

### Phase 2: ビルド検証

```bash
# 1. CIでビルド

# 2. アーティファクトをダウンロード

# 3. debパッケージの内容を検証 (インストール前に!)
mkdir /tmp/kernel-check
dpkg -x linux-image-*.deb /tmp/kernel-check
grep CONFIG_MODULE_SIG_FORCE /tmp/kernel-check/boot/config-*

# 期待値: # CONFIG_MODULE_SIG_FORCE is not set
# これが CONFIG_MODULE_SIG_FORCE=y なら使用禁止
```

### Phase 3: テスト環境で検証

```bash
# 1. VyOS VMを用意

# 2. VMにカーネルをインストール

# 3. 再起動して動作確認
#    - ネットワーク接続
#    - モジュールロード (modprobe nf_conntrack)
#    - 基本機能 (ping, SSH)

# 4. 問題なければ本番へ
```

### Phase 4: 本番適用

```bash
# 1. メンテナンス時間を確保 (最低1時間)

# 2. 物理コンソールアクセスを確保

# 3. 設定バックアップ (再確認)
show configuration commands > /config/backup-$(date +%Y%m%d-%H%M).txt

# 4. カーネルインストール
sudo dpkg -i linux-image-*.deb

# 5. インストール後、再起動前に確認
ls /boot/vmlinuz-*
# 複数のカーネルがあることを確認

# 6. 再起動
sudo reboot

# 7. 問題発生時: GRUBで旧カーネルを選択
```

### Phase 5: ロールバック手順

```bash
# GRUBメニューが出ない場合
# 起動直後に Shift または Esc を連打

# GRUBコマンドラインに入った場合
normal  # メニュー表示

# 旧カーネルで起動後、問題のカーネルを削除
sudo dpkg --purge linux-image-<問題のバージョン>
```

---

## 今回の復旧手順

1. VyOS ISOをUSBに書き込み
2. USBからブート
3. `install image` で再インストール
4. 再起動後、`scripts/backup-vyos-config.txt` の設定を適用

---

## 関連ファイル

- `scripts/recovery-vyos-config.sh` - 復旧スクリプト
- `scripts/backup-vyos-config.txt` - 設定バックアップ
- `.github/workflows/build-vyos.yml` - カーネルビルドCI

---

## 追加対策: CIワークフローの改善

### 1. configファイルをアーティファクトに含める

```yaml
- name: Save kernel config for verification
  run: |
    cp vyos-build/scripts/package-build/linux-kernel/linux/.config vyos-build/output/kernel-config

- name: Upload kernel config
  uses: actions/upload-artifact@v6
  with:
    name: kernel-config
    path: vyos-build/output/kernel-config
```

### 2. ビルド後の自動検証

```yaml
- name: Verify MODULE_SIG_FORCE is disabled
  run: |
    if grep -q "CONFIG_MODULE_SIG_FORCE=y" vyos-build/output/kernel-config; then
      echo "ERROR: MODULE_SIG_FORCE is still enabled!"
      exit 1
    fi
    echo "SUCCESS: MODULE_SIG_FORCE is disabled"
```

---

## チェックリスト (今後のカーネル更新時に使用)

- [ ] 現在の設定をバックアップした
- [ ] 現在のカーネルバージョンを記録した
- [ ] ビルドしたdebのconfigを検証した (MODULE_SIG_FORCE=n)
- [ ] テスト環境(VM)で動作確認した
- [ ] 物理コンソールアクセスを確保した
- [ ] GRUBで旧カーネル起動できることを確認した
- [ ] ロールバック手順を把握している
- [ ] メンテナンス時間を確保した (最低1時間)

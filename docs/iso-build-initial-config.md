# VyOS Custom ISO - 初期設定の埋め込み

カスタムビルドしたVyOS ISOに初期設定を埋め込む仕組み。

---

## 概要

GitHub ActionsでVyOS ISOをビルドする際、以下を自動的に埋め込む:

1. **初期設定ファイル** (`initial-config.boot`)
   - eth0: 192.168.1.1/24
   - SSH有効化 (eth0でリスニング)
   - タイムゾーン: Asia/Tokyo

2. **driver-checkスクリプト**
   - ドライバー検証ツール
   - カーネルバージョン、モジュール署名、SSH状態、ネットワーク設定を確認

---

## ファイル構成

| ファイル | 用途 |
|---------|------|
| `scripts/ci/initial-config.boot` | VyOS初期設定 (config.boot形式) |
| `scripts/ci/embed-initial-config.sh` | ISO埋め込みスクリプト |
| `scripts/ci/driver-check.sh` | ドライバー検証ツール |
| `scripts/ci/build-kernel-and-modules.sh` | カーネル+ISO統合ビルド |

---

## 初期設定の内容

### ネットワーク設定

```
interfaces {
    ethernet eth0 {
        address 192.168.1.1/24
        description "LAN (Initial Config)"
    }
}
```

### SSH設定

```
service {
    ssh {
        listen-address 192.168.1.1
        port 22
    }
}
```

### システム設定

- **ホスト名**: vyos
- **タイムゾーン**: Asia/Tokyo
- **シリアルコンソール**: ttyS0 (115200)
- **ログイン**: vyos/vyos (デフォルト)

---

## driver-check の確認項目

ISO起動後、`driver-check` コマンドで以下を確認:

| 項目 | 内容 |
|------|------|
| カーネルバージョン | 6.6.117-vyos (カスタム) |
| モジュール署名 | MODULE_SIG_FORCE有効確認 |
| ネットワーク設定 | eth0のIPアドレス、UP/DOWN |
| SSH状態 | SSHサービス起動、リスニングアドレス |
| ixgbeドライバー | Intel X540-T2検出、モジュールロード |
| r8126ドライバー | RTL8126検出、モジュールロード |
| インターフェース一覧 | 全NICの状態表示 |

**実行例**:

```bash
[VyOS] driver-check
```

**出力**:

```
========================================
  VyOS Custom ISO - Driver Verification
========================================

[INFO] Checking kernel version...
[OK] Running kernel: 6.6.117-vyos
[OK] Custom VyOS kernel detected

[INFO] Checking module signature enforcement...
[OK] MODULE_SIG_FORCE is enabled (signature required)
[OK] MODULE_SIG is enabled

[INFO] Checking network configuration...
[OK] eth0 IP address: 192.168.1.1/24
[OK] eth0 is UP

[INFO] Checking SSH service...
[OK] SSH service is running
[OK] SSH listening on: 192.168.1.1:22

[INFO] Checking Intel IXGBE driver (X540-T2)...
[OK] ixgbe module found in kernel
[OK] Intel X540-T2 PCI device detected
[OK] ixgbe module is loaded
[OK] Network interfaces using ixgbe: eth1 eth2

[INFO] Checking Realtek r8126 driver (5GbE)...
[OK] r8126 module found in kernel
[OK] Realtek RTL8126 PCI device detected
[OK] r8126 module is loaded
[OK] Network interfaces using r8126: eth3

========================================
  VERIFICATION PASSED: All drivers OK
========================================
```

---

## ビルドフロー

1. **GitHub Actions**: `build-vyos-custom-iso.yml`
2. **スクリプトコピー**:
   - `build-kernel-and-modules.sh`
   - `embed-initial-config.sh`
   - `initial-config.boot`
   - `driver-check.sh`
3. **Dockerコンテナ内実行**:
   - カーネルビルド
   - r8126モジュールビルド
   - **初期設定埋め込み** (`embed-initial-config.sh`)
   - ISOビルド
4. **成果物**:
   - `vyos-custom-*.iso` (初期設定+driver-check埋め込み済み)

---

## 初回起動時の手順

1. **ISOから起動**
2. **ログイン**: vyos/vyos
3. **driver-check実行**:
   ```bash
   [VyOS] driver-check
   ```
4. **SSH接続確認**:
   ```bash
   [Mac] ssh vyos@192.168.1.1
   ```

---

## トラブルシューティング

### eth0にIPアドレスが設定されていない

初期設定が読み込まれていない可能性:

```bash
[VyOS] show configuration
```

config.boot.defaultが適用されているか確認。

### driver-checkコマンドが見つからない

埋め込みスクリプトが実行されなかった可能性:

```bash
[VyOS] ls -la /usr/local/bin/driver-check
```

### ixgbeモジュールがロードできない

署名キーの問題:

```bash
[VyOS] sudo dmesg | grep -i "key was rejected"
[VyOS] sudo modprobe ixgbe
```

CONFIG_MODULE_SIG_FORCEが有効な場合、正しい署名キーでビルドされたモジュールのみロード可能。

---

## 参考

- VyOS config.boot形式: https://docs.vyos.io/en/latest/configuration/system/index.html
- VyOS Build: https://github.com/vyos/vyos-build
- カーネルモジュール署名: https://www.kernel.org/doc/html/latest/admin-guide/module-signing.html

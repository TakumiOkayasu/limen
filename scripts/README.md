# VyOS設定スクリプト

VyOSルーターの設定を楽にするためのスクリプト集。

## 必要環境

- VyOS Rolling Release (Debian 12ベース)
- Python 3.9以上 (VyOSに同梱)
- (オプション) PyYAML: `pip3 install pyyaml`

## ファイル構成

```
scripts/
├── vyos_config.py       # VyOS設定コマンド生成
├── wg_client_config.py  # WireGuardクライアント設定生成
├── verify_config.sh     # 設定確認スクリプト
├── config.yaml.example  # 設定ファイルサンプル
└── README.md
```

## 使い方

### 1. 設定ファイルの準備

```bash
# サンプルをコピー
cp config.yaml.example config.yaml

# 環境に合わせて編集
vim config.yaml
```

### 2. 設定コマンドの生成

```bash
# Phase 0 (基本設定) のコマンドを生成
python3 vyos_config.py phase0

# Phase 2 (IPv6) のコマンドを生成
python3 vyos_config.py phase2

# 全フェーズのコマンドを一括生成
python3 vyos_config.py all > all_commands.txt

# SSH公開鍵を指定して Phase 1 を生成
python3 vyos_config.py phase1 --ssh-key "AAAAC3NzaC1lZDI1NTE5..."
```

### 3. VyOSへの適用

生成されたコマンドを確認してから、VyOSで実行:

```bash
# 出力をクリップボードにコピー (macOS)
python3 vyos_config.py phase0 | pbcopy

# VyOSにSSH接続して貼り付け
ssh vyos
# 貼り付けて実行
```

### 4. WireGuardクライアント設定

```bash
# VyOSの公開鍵を取得
ssh vyos 'show wireguard keypairs pubkey default'

# クライアント設定を生成
python3 wg_client_config.py \
  --name phone \
  --server-pubkey <VyOS公開鍵> \
  --endpoint router.example.com:51820

# QRコード付きで生成 (スマホ用)
python3 wg_client_config.py \
  --name phone \
  --server-pubkey <VyOS公開鍵> \
  --qr

# ファイルに保存
python3 wg_client_config.py \
  --name laptop \
  --server-pubkey <VyOS公開鍵> \
  -o laptop.conf
```

### 5. 設定確認

```bash
# VyOSにスクリプトをコピーして実行
scp verify_config.sh vyos:/tmp/
ssh vyos 'bash /tmp/verify_config.sh'
```

## 注意事項

- スクリプトは設定コマンドを**出力するだけ**で、自動適用はしない
- 出力されたコマンドは**必ず内容を確認**してから実行
- `commit` と `save` を忘れずに実行
- Phase 1 でパスワード認証を無効化する前に、必ず公開鍵認証でログインできることを確認

## トラブルシューティング

### PyYAMLがない場合

```bash
# デフォルト値で動作する
python3 vyos_config.py phase0

# または、VyOSにPyYAMLをインストール
sudo pip3 install pyyaml
```

### インターフェース名が違う場合

VyOSで実際のインターフェース名を確認:

```bash
show interfaces
```

`config.yaml` の `wan_interface`, `lan_interface`, `wxr_interface` を修正。

### wgコマンドがない場合

WireGuardクライアント設定スクリプトには `wireguard-tools` が必要:

```bash
# macOS
brew install wireguard-tools

# Ubuntu
sudo apt install wireguard-tools
```

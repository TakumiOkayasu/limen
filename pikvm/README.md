# PiKVM セットアップ

VyOS自作ルーター管理用のPiKVM設定。

## ディレクトリ構成

```
pikvm/
├── README.md          # このファイル
├── config/            # 設定ファイル
│   └── backup/        # バックアップ (.gitignore対象)
└── scripts/           # 自動化スクリプト
    ├── backup-pikvm-config.sh      # 設定バックアップ
    └── check-pikvm-status.sh       # 状態確認
```

## セットアップ手順

詳細: [docs/pikvm-setup.md](../docs/pikvm-setup.md)

1. **初期セットアップ** - ネットワーク設定、SSH、パスワード変更
2. **VyOS連携設定** - シリアルコンソール、電源制御
3. **運用設定** - バックアップ、監視

## 運用スクリプト

### 状態確認

```bash
./scripts/check-pikvm-status.sh
```

### 設定バックアップ

```bash
./scripts/backup-pikvm-config.sh
```

デフォルトホスト: `pikvm.local`
環境変数で変更可能: `PIKVM_HOST=192.168.1.100 ./scripts/check-pikvm-status.sh`

## 関連ドキュメント

- セットアップ手順: `docs/pikvm-setup.md`
- トラブルシューティング: `docs/pikvm-troubleshooting.md`

## 物理接続

```
[VyOS] ──USB─── [PiKVM] ──HDMI─── [VyOS]
         (Serial/Console)    (Display Capture)
```

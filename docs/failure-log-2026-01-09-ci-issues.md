# 失敗記録: CI ワークフロー複合問題

**日付**: 2026-01-09
**影響**: CI連続失敗 (build-vyos + ci-auto-fix)
**深刻度**: 中

---

## 概要

VyOSカーネルビルドCIと自動修復CIが複数の問題で連続失敗した。

---

## 失敗原因と対策

### 1. build-vyos.yml: defconfigパス誤り

**症状**:
```
VyOS defconfig not found, searching...
/vyos/scripts/package-build/linux-kernel/arch/x86/configs/vyos_defconfig
Using kernel default config...
```

**根本原因**: defconfigのパスを `/vyos/packages/linux-kernel/` と想定していたが、実際は `/vyos/scripts/package-build/linux-kernel/` にあった。

**対策**:
```yaml
DEFCONFIG_PATH="/vyos/scripts/package-build/linux-kernel/arch/x86/configs/vyos_defconfig"
```

**再発防止**: defconfigが見つからない場合は即座にエラー終了するよう変更。

---

### 2. build-vyos.yml: MODULE_SIG未有効化

**症状**:
```
MODULE_SIG settings:
# CONFIG_MODULE_SIG is not set
```

**根本原因**: デフォルトのx86_64_defconfigを使用したため、VyOS固有のMODULE_SIG設定が欠落。

**対策**: VyOS defconfigを必須とし、MODULE_SIG=y の検証ステップを追加。
```bash
if ! grep -q "CONFIG_MODULE_SIG=y" .config; then
  echo "ERROR: CONFIG_MODULE_SIG is not enabled!"
  exit 1
fi
```

---

### 3. build-vyos.yml: kmodパッケージ不足

**症状**:
```
dpkg-checkbuilddeps: error: Unmet build dependencies: kmod
dpkg-buildpackage: warning: build dependencies/conflicts unsatisfied; aborting
```

**根本原因**: `bindeb-pkg` ターゲットは `kmod` パッケージを必要とする。

**対策**:
```bash
sudo apt-get install -y flex bison libelf-dev libssl-dev bc kmod
```

---

### 4. ci-auto-fix.yml: 書き込み権限不足 (403)

**症状**:
```
remote: Write access to repository not granted.
fatal: unable to access '...': The requested URL returned error: 403
```

**根本原因**: `workflow_run` トリガーのデフォルト権限では書き込みができない。

**対策**:
```yaml
permissions:
  contents: write
  pull-requests: write
```

---

### 5. ci-auto-fix.yml: workflows権限問題

**症状**:
```
remote rejected ... refusing to allow a GitHub App to create or update workflow
`.github/workflows/build-vyos.yml` without `workflows` permission
```

**根本原因**: GITHUB_TOKENでは `workflows` 権限を付与できない。ワークフローファイルの変更にはPATが必要。

**対策**: 制限事項をコメントで明記。ワークフローファイルの自動修復は現状不可。
```yaml
# Note: GITHUB_TOKEN cannot grant 'workflows' permission.
# Auto-fix for workflow files requires a PAT with 'workflow' scope.
```

**将来的対策** (オプション):
- リポジトリにPATをシークレットとして登録
- `token: ${{ secrets.PAT_WITH_WORKFLOW }}` で使用

---

### 6. ci-auto-fix.yml: grepオプション解釈問題

**症状**:
```
grep: unrecognized option '---FIX_START---'
```

**根本原因**: `---` がgrepのオプションとして解釈された。

**対策**:
```bash
grep -qF -- "---FIX_START---"  # -F: 固定文字列, --: オプション終了
```

---

## 修正コミット

1. `kmod` パッケージ追加
2. defconfigパスを `/vyos/scripts/package-build/linux-kernel/` に修正
3. MODULE_SIG=y の検証ステップ追加
4. ci-auto-fixにpermissions追加
5. grepの `--` オプション追加
6. 制限事項のコメント追記

---

## チェックリスト (CI修正時に確認)

- [ ] ビルド依存パッケージは全て列挙されているか
- [ ] パスは実際のコンテナ内構造と一致しているか
- [ ] 重要な設定項目 (MODULE_SIG等) の検証ステップがあるか
- [ ] permissionsは必要な権限を含んでいるか
- [ ] grepやsedの引数に `--` が必要か確認したか
- [ ] GITHUB_TOKEN vs PAT の権限制限を理解しているか

---

## 関連ファイル

- `.github/workflows/build-vyos.yml`
- `.github/workflows/ci-auto-fix.yml`
- `docs/failure-log-2026-01-07-kernel-update.md` (関連: カーネル問題)

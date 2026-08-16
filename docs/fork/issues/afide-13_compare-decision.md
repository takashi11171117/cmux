---
name: Agent-first IDE - Compare の実現方式決定
about: 未確定-03 と新規-D を解決する。Diff Viewer への .patch 受け渡しが成立するかを検証し、実装可否とセキュリティ制約を確定させる
title: '[AFIDE 13] Compare の実現方式決定（未確定-03 / 新規-D の解決）'
labels: research, agent-first-ide, afide-13, save-conflict
assignees: ''
---

## 🎯 目的

FR-08（Compare）の実現方式を決める。**現時点で FR-08 は未設計**であり、この issue が終わるまで実装 issue を立てられない。

決めるのは3点: (a) `.patch` の書き出しとライフサイクル、(b) マニフェスト生成側 `Native/DiffSidecar` の契約、(c) セキュリティ制約。加えて「Reload / Keep Mine の2択で先行リリースしてよいか」を確定させる。

## 📊 背景

詳細設計 §9.4 で、既存 Diff Viewer の制約が実コードから判明している。

- 既存 Diff Viewer は `cmux-diff-viewer` カスタムスキームを WebView に登録する方式で、配信対象は**トークンごとの allowlist に登録されたローカルファイル**である。`CmuxDiffViewerRegisteredFile` は `requestPath` / `fileURL` / `mimeType` / `fileSize` を持ち、**内容ではなくファイル URL を指す**
- 実際の登録は `registerFromManifest(token:now:)` 経由で、**オンディスクのマニフェスト**（`Native/DiffSidecar` が書く）から読む
- **許可 MIME は3種だけ**: `text/html` / `text/javascript` / `text/x-diff`。さらに拡張子が MIME と一致していなければ拒否される（`text/x-diff` は `.patch` のみ）
- **置き場所は1箇所に固定**: 全登録ファイルは trusted root（既定 `/tmp/cmux-diff-viewer-<uid>/`）の**内側**でなければ `unreadableFile` で拒否される。`NSTemporaryDirectory()` の下に書いても**受け付けられない**

**結論として「2ファイルを指すマニフェストを渡して Diff Viewer に差分を計算させる」方式は成立しない。** 成立しうる形は「アプリ側で unified diff を生成し、`.patch` 1本として trusted root の内側に書き、それを指すマニフェストを渡す」の1つだけである。

## ✅ タスクリスト

### 調査

- [ ] `Native/DiffSidecar` が書くマニフェストの JSON 形式を読み、**アプリ側から同形式を書けるか**を確認する（詳細設計では `[要調査]` のまま）
- [ ] `registerFromManifest(token:now:)` の受け入れ条件（トークンの発行元・寿命・パス検証）を読む
- [ ] `.patch` を trusted root 内に置いて Diff Viewer に描画させる**最小の実験**を行い、成立するかを確かめる
- [ ] 独立した比較 UI を作る案のコスト（新規 SwiftUI ビュー + diff 生成 + テーマ対応）と比較する

### セキュリティ制約の確定（新規-D。**満たさない限り Compare を実装しない**）

- [ ] 書き出す `.patch` には**ディスク側の内容と未保存バッファの内容が両方とも平文で載る**ことを前提に評価する（「一時ファイルが残る」程度の話ではない）
- [ ] **root を `0700`、`.patch` を `0600` で作る**方式が取れるか確認する。Diff Viewer 側の trusted root 検証は `lstat` で「ディレクトリであること」と「uid が自分であること」しか見ておらず、**ディレクトリの mode を検証していない**。`/tmp` は他ユーザーが traverse 可能なので、root が `0755` で作られていれば同一マシンの他ユーザーから未保存内容が読める
- [ ] **確実な unlink の条件を定義する**: 「パネルの close」「衝突の解決（Reload / Keep Mine）」「アプリ終了」の3つすべて
- [ ] **24時間保持との整合**: URL スキームハンドラ側のセッション寿命は `maxSessionAge = 24 * 60 * 60` 秒。ファイルを消してもセッション登録はしばらく残る。**ファイル削除とセッション失効のどちらが先でも壊れない**ことを確認する

### 判断

- [ ] 次の3択から1つを決める: (i) 既存 Diff Viewer に `.patch` 経由で渡す / (ii) 独立した比較 UI を作る / (iii) Compare を実装せず Reload / Keep Mine の2択で確定する
- [ ] **「Reload / Keep Mine の2択で先行リリースしてよいか」を確定させる。** 02 の FR-07 受け入れ条件1 は3択を求めており、詳細設計が2択で確定させたわけではない。afide-12 のマージ可否がこの判断に依存する
- [ ] 決定と根拠を `docs/fork/` に記録する（既存の設計書 §9.4 / 新規-D への追記でもよい）
- [ ] (i) または (ii) を採る場合、後続の実装 issue に必要なタスク（diff 生成 / ファイル権限 / unlink / テスト）を洗い出して記録する

## 📦 成果物

- [ ] `Native/DiffSidecar` のマニフェスト契約の調査結果
- [ ] `.patch` を trusted root に置いて描画させる実験の結果（成立 / 不成立とその理由）
- [ ] セキュリティ制約4点（root `0700` / ファイル `0600` / 確実な unlink / 24h セッションとの整合）が満たせるかの判定
- [ ] Compare の実現方式の決定（(i) / (ii) / (iii)）と根拠
- [ ] **「2択で先行リリースしてよいか」の決定**
- [ ] (i)(ii) を採る場合は、後続実装 issue に必要なタスクの一覧

## 📝 備考

- この issue は調査 issue であり、`docs/fork/` 以外の変更は実験用のローカル差分にとどめる（本体にコミットしない）
- **FR-08 の実装 issue はこの issue が終わるまで作れない。** 実現方式が未決のまま「Compare を実装する」issue を立てると、タスクリストも成果物も書けない
- 実験で Diff Viewer 側のコードを読む際、`Packages/macOS/CmuxBrowser/.../DiffViewer/` と `Sources/Panels/CmuxDiffViewerURLSchemeHandler.swift` の両方が対象になる

## 🔗 関連

- 依存: **afide-02 完了後に着手**（他の feature issue とは独立。並行可）。**afide-12 のマージ可否がこの issue の判断に依存する**
- 由来: FR-08（Compare の実体）、FR-07 受け入れ条件1・6、REQ-20
- 設計書: `docs/fork/03_詳細設計.md` §9.4、§20.1、§20.5、新規-D
- 未確定事項: **未確定-03（Compare の実体 + 2択先行リリースの可否）を本 issue で解決する**。新規-D（`.patch` 書き出しとセキュリティ制約）も本 issue で解決する

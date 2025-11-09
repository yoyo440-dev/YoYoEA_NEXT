# Repository Guidelines

## CODEX
-会話は日本語でお願いします。
-実施したアクションはタイムスタンプ付きで/home/anyo_/workspace/YoYoEA_NEXT/Memo/memo.txtに記録しアップデートしてください。アクション内容、結果を詳細記録お願いします。日本語　UTF-8
-次のアクションがある場合はメモに記録してください。コード開発以外の会話は記録しなくていいです。
-コード改良を実施した際には、ある程度まとまった時点でコミットメッセージとともに提案してください。

## プロジェクト構成とモジュール配置
EA本体は `YoYoEA_Multi_Entry/MQL4/Experts/YoYoEA_Multi_Entry.mq4` に配置されています。追加のMQL4モジュールを置く場合も同ディレクトリにまとめ、共有状態は既存の `g_*` グローバル変数を通じて扱ってください。ATRバンド設定CSVは `YoYoEA_Multi_Entry/Config` に保存し、`{PROFILE}` プレースホルダーが `InpProfileName` と連動します。旧設定は `Config/archive` に退避済みです。ストラテジーテスター用プリセット（.set）は `priset/` で BETR_* 命名に統一し、運用スクリプトは `Scripts/` 配下に格納します。作業ログは `Memo/memo.txt` にISO形式タイムスタンプと日本語で追記することをルールとします。StateLogger を含む ML 連携コードは `YoYoEA_Multi_Entry_ML/` にまとめてください。

## ビルド・テスト・開発コマンド
MetaEditor を利用した一括コンパイルは `pwsh ./Scripts/compile_YoYoEntryTester.ps1` を実行します。スクリプト内の `metaEditor`、ソース、出力パスは Windows 側の MT4 配置に合わせて更新してください（既定値は `D:\Rakuten_MT4` を想定）。実行すると `.mq4` をコピーし、MetaEditor を `/portable` オプションで起動して `D:\EA開発2025_10_26\CompileLog` にログを生成します。MT4 ターミナルの再起動は `pwsh ./Scripts/run_Rakuten_MT4.ps1` を使用します。個別にコンパイルする場合は `metaeditor.exe /portable /compile:"<path>\YoYoEA_Multi_Entry.mq4" /log:"<log>"` を直接呼び出してください。StateLogger 系は `YoYoEA_Multi_Entry_ML/MQL4/Experts/MarketStateLogger.mq4` を対象に同手順で扱います。

## コーディングスタイルと命名規約
3スペースインデントを徹底し、関数は `CamelCase`、構造体は `PascalCase`、列挙体は大文字スネークで表記します。新規 extern 入力には `Inp`、モジュール内の状態には `g_`、定数には `k` を接頭辞として付与します。`#property` ブロックと入力項目の順序は `YoYoEA_Multi_Entry.mq4` 冒頭の構成を踏襲し、セクション区切りには `//+------------------------------------------------------------------+` 形式のバナーコメントを利用します。成果物は `TradeLog_<Profile>.csv`、ATR設定は `AtrBandConfig_<Profile>.csv` という命名規約を守ってください。

## テスト指針
バックテストは MetaTrader4 ストラテジーテスター（Ctrl+R）で実施します。まず `priset/` の基準セットを読み込み、ATRバンド検証時は `InpUseAtrBandConfig` を true にして `InpAtrBandConfigFile` を `MQL4/Files` 内の対象CSVへ指定します。テスト後は `TradeLog_<Profile>.csv` とターミナルログでスプレッド制御、マルチポジション制限、ストップ更新の挙動を確認し、役目を終えた検証用CSVは `Config/archive` へ整理してください。回帰確認や共有が必要な場合は、主要スクリーンショットや損益表を併せて保管します。

## コミットとプルリクエスト指針
コミットは粒度を小さく保ち、履歴で使われている書式（例: `v1.23 マルチポジション対応`, `Add ATR band config variations`）に揃えた件名を採用します。要約には影響を与えるストラテジーやバージョンを先頭で示し、背景が分かりにくい変更は本文で補足してください。プルリクエストでは調整したパラメータ、影響する設定ファイルやプリセット、使用した MT4 ビルド、主要バックテスト結果（エクイティカーブや `TradeLog` の差分）を添付します。レビュー依頼前に `Memo/memo.txt` の最新状態を反映し、次の担当者が手順を引き継げるようにしてください。

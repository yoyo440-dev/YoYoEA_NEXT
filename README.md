# YoYoEA_NEXT
YoYoEA_NEXT は複数ストラテジー（MA、RSI、CCI、MACD、Stochastic）のエントリー精度を検証するための MQL4 エキスパートアドバイザーです。各ストラテジーの有効／無効やリスク制御パラメータを柔軟に設定し、バックテストやフォワードテストで挙動を記録します。

## 主な機能
- 複数戦略の同時評価：5 種類のテクニカル指標シグナルを個別に監視して注文を発行
- ATR バンド設定：CSV からストラテジー別の停止・利確条件を読み込み、ATR・pips のいずれかで管理
- エントリー制御強化
  - スプレッド上限（`InpMaxSpreadPips`）の超過で発注をスキップ
  - ATR 値が取得できない場合は自動で pips ベースにフォールバック
  - リスク一定ロット（`InpUseRiskBasedLots`）によるポジションサイズ調整
  - ブローカー制約に合わせたロット正規化と証拠金チェック
- マルチポジション・ロット制御（v1.23 以降）
  - `InpMaxPositionsPerStrategy` で各ストラテジーの保有上限を設定し、`InpAllowOppositePositions` と併用して総ポジション数を管理
  - エクイティ閾値（`InpMultiPositionEquityThreshold`）を下回ると自動的にマルチポジションを停止
  - 追加の閾値（`InpLotReductionEquityThreshold`, `InpLotReductionFactor`）で資産減少時のロット縮小に対応
- 稼働ガード
  - 戦略ごとのクールダウン／連敗休止 (`InpCooldownMinutes`, `InpLossStreakPause`, `InpLossPauseMinutes`)
  - 既存ポジションと逆方向のシグナルを抑制 (`InpAllowOppositePositions`)
  - 取引時間帯フィルタと金曜カットオフ (`InpUseTradingSessions`, `InpSessionStartHour`, `InpSessionEndHour`, `InpSessionSkipFriday`, `InpFridayCutoffHour`)
- 詳細ログ出力：エントリー／決済を CSV に記録し、パラメータスナップショットや ATR バンド適用状況をコンソールに出力

## 入力パラメータの補足
- `InpUseRiskBasedLots = true` の場合、損切り距離（ATR／pips）から口座残高に対するリスク％（`InpRiskPercent`）でロットを算出します。
- `InpLossStreakPause` に達した損失連続数で休止し、`InpLossPauseMinutes` が 0 の場合は再開条件を外部で整えるまで停止します。
- 取引セッションはサーバー時間を基準とし、`InpSessionStartHour` ≤ 時刻 < `InpSessionEndHour` の間のみ発注します。金曜は `InpSessionSkipFriday = true` と `InpFridayCutoffHour` で早期停止が可能です。

## ログファイル
- トレードログ：`TradeLog_<Profile>.csv` – ENTRY/EXIT 双方を記録。価格やインジケータ値に加え、`atr_entry` / `atr_exit` 列でそれぞれの ATR を保持し、損益（`net`）、獲得 pips、`exit_reason`（`TAKE_PROFIT` / `STOP_BREAKEVEN` / `STOP_TRAILING` / `STOP_LOSS` / `MANUAL_*`）を追跡

## ビルドと配置
1. PowerShell で `Scripts/build_experts.ps1` を実行すると、MQL4/Experts 配下の EA をまとめてコンパイルできます。
   ```powershell
   pwsh ./Scripts/build_experts.ps1
   ```
2. 生成された `.ex4` を MT4 の `Experts` ディレクトリへ配置し、テスターでパラメータを調整してバックテストを実施してください。

## テストと運用のポイント
- 新規パラメータを組み合わせたバックテストで、スプレッド制御・連敗休止・セッション抑制が期待通りログに出力されるか確認してください。
- 取引サーバーのタイムゾーンと `InpSession*` の設定が一致しているか事前に確認してください。
- ATR バンド CSV の設定が不足している場合、デフォルト値にフォールバックします。テスト開始時のログで読み込み結果をチェックすることをおすすめします。

## ATRバンドCSVフォーマット
- CSV は『minAtr,maxAtr,<Strategy>_Enable,<Strategy>_Mode,<Strategy>_SL,<Strategy>_TP』の列を戦略ごとに持ちます。
- デフォルトの列順: MA / RSI / CCI / MACD / STOCH。見出し名が一致すれば順番入れ替えや一部省略も可能。
- Mode は GLOBAL/ATR/PIPS を指定し、SL/TP は ATR 倍率または pips 値を入力します。
- Enable を OFF にすると該当ストラテジーは該当帯域でシグナルを無効化します。
- サンプル: minAtr,maxAtr,MA_Enable,MA_Mode,... を参照し、必要に応じて帯域を追加してください。

## v1.23 で追加された主な仕様
- Multi-Position サポート
  - `InpMaxPositionsPerStrategy` と有効ストラテジー数から総保有上限を算出し、`InpAllowOppositePositions=true` 時に複数ポジションを許可
  - `InpMultiPositionEquityThreshold` を下回ると自動的にシングルポジション運用へ切り替え
- ロット縮小ロジック
  - `InpLotReductionEquityThreshold` で指定したエクイティを割ると、固定ロット運用時に `InpLotReductionFactor` を乗じたロットで発注
- ログ拡張
  - TradeLog に `atr_entry` / `atr_exit` 列を追加し、ENTRY/EXIT 両方の ATR 状態を記録。ENTRY ログは廃止済み
- 互換性
  - 新パラメータはすべて任意で、既存設定（シングルポジション・固定ロット）のままでも過去バージョンと同じ動作を維持します。


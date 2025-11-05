# Repository Guidelines

## Project Structure & Module Organization
`YoYoEA_NEXT/MQL4/Experts/YoYoEntryTester.mq4` hosts the Expert Advisor; keep additional MQL4 modules beside it and guard shared state in `g_*` globals. ATR band definitions live in `YoYoEA_NEXT/Config`, with `{PROFILE}` placeholders that map to `InpProfileName`; retire old variants under `Config/archive`. Strategy Tester presets (.set) sit in `priset/` and mirror the BETR naming. Automation scripts are under `Scripts/`, and `Memo/memo.txt` tracks agent actions—append entries in Japanese with ISO timestamps at every meaningful change.

## Build, Test, and Development Commands
Run `pwsh ./Scripts/compile_YoYoEntryTester.ps1` after adjusting the `metaEditor`, source, and target paths to your local MetaTrader install (default assumes `D:\Rakuten_MT4`). The script copies the `.mq4`, invokes MetaEditor with `/portable`, and drops logs in `D:\EA開発2025_10_26\CompileLog`. Launch MetaTrader via `pwsh ./Scripts/run_Rakuten_MT4.ps1` when you need to refresh data. For ad-hoc builds, call `metaeditor.exe /portable /compile:"<path>\YoYoEntryTester.mq4" /log:"<log>"` directly.

## Coding Style & Naming Conventions
Follow the existing MetaEditor layout: three-space indentation, `CamelCase` function names, `PascalCase` structs, and screaming-snake enums. Prefix new extern inputs with `Inp`, module-level state with `g_`, and constants with `k`. Keep `#property` directives and input groups ordered as in `YoYoEntryTester.mq4:1`. Use banner comments (`//+---`) to delimit sections and mirror the logging phrasing already in place. Name generated CSV artefacts `TradeLog_<Profile>.csv` and ATR configs `AtrBandConfig_<Profile>.csv`.

## Testing Guidelines
Always backtest with MetaTrader 4’s Strategy Tester (Ctrl+R). Load a baseline preset from `priset/`, point `InpAtrBandConfigFile` to the relevant CSV in `MQL4/Files`, and enable `InpUseAtrBandConfig` when validating ATR bands. After each run, review `TradeLog_<Profile>.csv` in `MQL4/Files` plus the Terminal log to confirm spread filters, multi-position gating, and stop logic updates. Capture key screenshots or CSV snippets for regressions and stash exploratory configs in `Config/archive` once superseded.

## Commit & Pull Request Guidelines
Keep commits small with concise subject lines that match history (`v1.23 マルチポジション対応`, `Add ATR band config variations`). Reference affected strategy or version early in the summary, omit trailing periods, and explain rationale in the body if non-obvious. Pull requests should list tuned parameters, affected config/preset files, the MT4 build used, and attach or link backtest evidence (equity curve plus `TradeLog` delta). Update `Memo/memo.txt` with the actions you took before requesting review so the next agent can pick up context instantly.

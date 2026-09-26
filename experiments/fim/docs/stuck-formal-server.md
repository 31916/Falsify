# Stuck-at 本実験：Linuxサーバ

## 固定条件

- ブランチ `FIMStuck`。トルク比の `FIMトルク` と別のチェックアウトで実行する。
- 注入箇所：`Transmission/TransmissionRatio/gear` とギア比Lookupの間。
- FIMネイティブのStuck-at回路で、故障開始直前のギア指令値を保持し、終了時に現在の指令へ戻す。
- 開始時刻 5 / 10 / 15 秒 × 継続時間 0.2 / 0.5 / 1.0 秒。予備実験から変更しない。
- シミュレーション30秒、アクセル60–100%、5秒ごと6値、ブレーキ0、ode5 / 0.01秒。
- 要件：20秒以内に95 mph以上へ到達する。ギアは指令・故障後とも厳密に `{1,2,3,4}`。
- RAND / ACER / A3C / DDQN / Ψ-TaLiRo、各条件100独立試行、1試行最大1500入力。
- 初期データ収集も1500入力に含む。学習状態は試行ごとに破棄。最初の有効な反例で終了。
- 合計4500試行。入力数の理論上限は675万本（独立再検証と事前検査は別）。
- 1ワーカー・数値計算1スレッド、CPUのみ。同一サーバ内で比較する。

| 故障 | 開始 [秒] | 継続 [秒] |
|---|---:|---:|
| S01 | 5 | 0.2 |
| S02 | 5 | 0.5 |
| S03 | 5 | 1.0 |
| S04 | 10 | 0.2 |
| S05 | 10 | 0.5 |
| S06 | 10 | 1.0 |
| S07 | 15 | 0.2 |
| S08 | 15 | 0.5 |
| S09 | 15 | 1.0 |

予備実験の0/130は全入力に対する安全性の証明ではない。一方、本実験で違反が出る保証もない。
全件未発見なら「この条件・予算では差を検出できなかった」と報告し、学習不足や安全性を断定しない。
Macのトルク比実験との実時間を、同一計算環境の比較として扱わない。

## 事前検査と保存物

`prepare` は正常モデルと9故障モデル、対応するFalsify wrapperを生成する。
生成には従来どおり `FISingle` / `FCSingle` とCSVを使う。手書きの代替故障回路は使わない。
ソース、モデル、条件、実行環境情報を保存し、SHA-256で固定する。

`launch` はSSH切断に影響されないプロセスを開始し、以下を実行する。
いずれかの検査が失敗したら本実験には進まず、`status.json` にエラーを記録する。

1. ネイティブStuck-atの固定・解除・無効化の18検査。
2. 予備実験の事前固定入力I121で全9故障を再実行し、開始前一致・故障無効時一致を検査。
3. 正常モデル128入力（64端点組合せ＋独立64 LHS）。有限検査であり恒真性の証明ではない。
4. 正常モデルでRAND 2、A3C 2、ACER 12、DDQN 90、Ψ-TaLiRo 102入力を実行。
   A3C更新、ACERオンライン・経験再生更新、DDQN更新、Ψ-TaLiRoの初期100 LHS後の適応探索を実測する。
5. 全9故障のFalsify wrapperをそれぞれRAND 2入力で動かし、共通モデルへの独立再入力で照合する。
6. `preflight.json` が `PASS` の場合のみ、4500試行へ進む。

本実験の各試行でも、最初の入力と反例候補は故障モデル・正常モデル・故障無効モデルで再実行する。
反例は同じ入力で故障モデルだけが違反し、波形再現・正常モデル合格・無効時正常一致を満たす必要がある。
再検証時間は探索時間と分離する。エラーを「未発見」や「反例」として数えない。

`fault_catalog.csv`、`generation_S*/Configuration/{faults,enable}.csv` に注入指定が残る。
`trials/Sxx_METHOD_SEED/` に `candidates.jsonl`（全入力・頑健度・更新回数）、`best.mat`、
`best-trace.csv`、`verification_*/`、`result.json` を保存する。
`verification.mat` には0.04秒刻みの元ギア指令ログも残し、ギア値を丸めずに検査する。
`runtime.json` はPython依存バージョンとサーバ識別情報、`protocol.json` はcommitと全条件、
`code_snapshot/` と `source-hashes.json` はコードの監査用。

## このサーバでの実行

専用ルート：`/home/haruto/research/falsify-fim-stuck-20260926`。
MATLAB：`/usr/local/MATLAB/R2026a/bin/matlab`。Python 3.9.6。
専用 `.venv-falsify` と `.venv-fim-psy` を使い、既存研究用のPython環境は変更しない。
固定版依存 `.deps/fim` は `dependencies/prepare.py` で全ハッシュを照合する。
CPU版PyTorchは `2.3.1+cpu`、それ以外の直接依存は既存の固定requirementsを使用する。

```sh
cd /home/haruto/research/falsify-fim-stuck-20260926
export FIM_MATLAB=/usr/local/MATLAB/R2026a/bin/matlab
export FIM_PSY_PYTHON="$PWD/.venv-fim-psy/bin/python"
export PATH=/usr/local/MATLAB/R2026a/bin:$PATH
export MATLAB_PREFDIR="$PWD/.runtime/matlab-prefs"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1
"$FIM_MATLAB" -singleCompThread -batch "addpath('experiments/fim'); setup_fim; setup_fim_linux;"
.venv-falsify/bin/python experiments/fim/python/run_stuck_campaign.py prepare results/fim/stuck/stuck_main_20260926_v1
.venv-falsify/bin/python experiments/fim/python/run_stuck_campaign.py launch results/fim/stuck/stuck_main_20260926_v1
```

進捗は実行フォルダの `status.json`、`campaign.log` と各試行の `candidates.jsonl`。
途中結果CSVは次で出力できる（完了した試行だけを集計し、未完了を失敗にしない）。

```sh
.venv-falsify/bin/python experiments/fim/python/summarize_torque_campaign.py results/fim/stuck/stuck_main_20260926_v1
```

共通処理名に `torque` が残る箇所は実装を共有するためであり、注入故障の意味ではない。
`fault_family=stuck` と故障カタログでモデルを明示的に切り替える。
停止要求は実行フォルダの空ファイル `STOP_AFTER_TRIAL`。現在の試行が完了してから停止する。
試行途中の失敗・不完全な出力は自動再試行しない。原因を確認してから再開を判断する。

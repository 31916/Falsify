# 2026-09-28 サーバ同時再実行

ユーザー指定により旧Macトルク比本実験と旧サーバStuck-at本実験を停止し、
本実験の生データ・集計コピーをバックアップせず削除した。旧結果の再利用はしない。
ソース・故障条件・予備実験は保存。サーバ再起動後に両方を新規実行する。

## 固定条件

- トルク比: −0.02, −0.03, −0.04, −0.05, −0.10。5故障×5手法×100試行 = 2500試行。
- Stuck-at: 開始5/10/15秒×持続0.2/0.5/1秒。9故障×5手法×100試行 = 4500試行。
- RAND / ACER / A3C / DDQN / Ψ-TaLiRo。最大1500入力、初期学習・100点LHS込み。
- 最初の独立再検証済み反例で停止。正常モデル照合・故障無効化照合を従来どおり実施。
- 30秒、アクセル60–100%、5秒刻み6区間、ブレーキ0。
- 20秒以内に95mph以上、ギアは厳密に1/2/3/4。ode5、0.01秒。
- 学習設定と乱数100個は従来の設定ファイルのまま。学習は毎試行初期化する。

## 並列化で変えたこと

`config/parallel_execution.json` を従来の条件に重ねる。
両実験とも同じサーバ・MATLAB R2026aで4ワーカー×4論理CPU、合計8ワーカー×32論理CPU。
4ワーカーは独立試行の同時実行であり、A3C内部の学習ワーカーを4にする変更ではない。
MATLAB数値計算、BLAS、Torchのスレッド上限は4。CPU affinityでも4論理CPUに制限する。

| ワーカー | トルク比の論理CPU | Stuck-atの論理CPU |
|---|---|---|
| 0 | 0,1,16,17 | 2,3,18,19 |
| 1 | 4,5,20,21 | 6,7,22,23 |
| 2 | 8,9,24,25 | 10,11,26,27 |
| 3 | 12,13,28,29 | 14,15,30,31 |

各組はPコア1個（SMT2スレッド）とEコア2個。両実験に同じ構成を割り当てる。
同一故障・同一seedの5手法は同じワーカーで実行し、手法順を事前にシャッフルする。
各故障・各手法の100試行を各ワーカーに25試行ずつ配る。結果を見て割当ては変えない。
新しいPython/MATLABプロセス、作業場所、MATLAB設定、Simulinkキャッシュを毎試行分離する。

**4論理CPUは4物理コアではなく、4倍速を保証しない。** 実時間は並列負荷下の測定であり、
サーバ負荷、共有メモリ帯域、終盤の空きワーカーなどによる干渉は残る。
`execution.json` のワーカー・CPU・開始終了時刻と、`server-resources.jsonl` を併記して評価する。
旧Mac/サーバ結果の時間と混ぜない。探索時間・独立再検証時間・プロセス全体時間を区別する。

## 実行と安全確認

各ブランチのクリーンなLinux checkoutで以下を実行する。
`FIM_MATLAB` と `FIM_PSY_PYTHON` は専用環境の絶対パスを設定する。

```sh
.venv-falsify/bin/python experiments/fim/python/run_parallel_campaign.py prepare ABSOLUTE_TORQUE_CAMPAIGN torque
.venv-falsify/bin/python experiments/fim/python/run_parallel_campaign.py prepare ABSOLUTE_STUCK_CAMPAIGN stuck
.venv-falsify/bin/python experiments/fim/python/run_parallel_campaign.py launch ABSOLUTE_TORQUE_CAMPAIGN ABSOLUTE_STUCK_CAMPAIGN
```

最後の `launch` は1回だけ。SSH切断後も独立した管理プロセスが継続する。
両実験の正常128入力、学習更新開始、全故障の独立再実行、Stuck-atネイティブ回路を再検査する。
両方PASS後、8プロセス同時の正常モデル検査を行い、これもPASSしてから本実験8ワーカーを開始する。
事前検査は本実験の100試行には数えない。1つでもプロセス異常があれば両実験を停止し、
エラーを反例・未発見として集計しない。途中結果の自動再開・自動再試行はしない。

進捗は各campaignの `status.json` と `workers/0..3/status.json`。
個別結果は `trials/CASE_METHOD_SEED/`、CPU割当・全体時間は各試行の `execution.json`。
終了後に両実験のCSVと集計監査を生成する。

この再実行では両ブランチを同一ソースcommitに合わせる。依存環境は同じバージョンを使用するが、
両実験のモデル、結果、書き込み先は分離する。設定・ソース・モデルは試行前にハッシュ照合する。

# トルク比本実験の事前検査

これは本実験2500試行の結果ではなく、開始前の検査記録である。
実行コードは `c35adbe29565cf9a8f1f0fed5e77aa0bf91d62e4`。
`execution-provenance.json` の40件のソースハッシュは、このcommitのGit blobと一致確認済み。

- 正常128入力: 全件満足。最小車速余裕1.144657813 mph。
- RAND: 2入力、接続・独立再実行確認。
- A3C: 2入力、4更新。
- ACER: 12入力、オンライン24更新＋経験再生6更新。
- DDQN: 90入力＝540遷移、40更新。
- Ψ-TaLiRo: 102入力、うちLHS100入力の後に適応的探索2回、GP学習2回。
- T01/T04/T05/T02/T03: 各2入力で注入・探索モデルと独立モデルの一致を確認。

`baseline-inputs.csv` は全128入力の6アクセル値、`baseline-results.csv` は全判定結果。
`preflight.json` は各検査の実測記録、`fault_catalog.csv` は5故障の対応表。
`protocol.json` は本実験の固定条件で、事前検査と本実験の予算・seedを混同しない。

全ローカル出力: `results/fim/comparison/torque_main_20260926_v1/`。
本実験の進捗は同フォルダの `status.json`、実入力は `trials/*/candidates.jsonl` に記録する。
これらの準備結果を100試行の成績に流用していない。

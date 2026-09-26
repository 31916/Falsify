# FIMによるAT内部故障実験

FIMの `FISingle` で故障ブロックを挿入し、`FCSingle` で有効化する。
元のARCH ATモデル・既存ARCH要件・Falsify coreは変更しない。

## 現行実験

| 実験 | 設定 | 実行入口 |
|---|---|---|
| トルク比の本実験 | `config/torque_comparison.json` | `python/run_torque_campaign.py` |
| ギア指令Stuck-atの予備実験 | `config/stuck_preliminary.json` | `python/run_stuck_preliminary.py` |
| ギア指令Stuck-atのサーバ本実験 | `config/stuck_comparison.json` | `python/run_stuck_campaign.py` |

[本実験条件](docs/formal-protocol.md) ／ [Stuck-atの実装と検査](docs/stuck-preliminary.md)

本実験: −0.02/−0.03/−0.04/−0.05/−0.10 × RAND/ACER/A3C/DDQN/Ψ-TaLiRo × 100独立試行。
1試行最大1500入力、初期学習用入力も含む。最初の再検証済み反例で停止する。
Stuck-atの固定130入力の予備実験とは別に、同じ9故障で5手法×100試行の本実験を行う。
Linux専用の準備・事前検査・実行方法は [Stuck-at本実験](docs/stuck-formal-server.md) を参照。

## 配置

- `config/`: 条件。本実験の故障と100 seedsは `torque_comparison.json`。
- `matlab/`: FIMモデル生成、Simulink実行、Falsify接続、波形検査。
- `python/`: 実行管理、Ψ-TaLiRo接続、入力設計、CSV監査・集計。
- `tests/`: 学習更新、STL境界、ネイティブStuck-at回路の検査。
- `dependencies/`: 固定commit・ライセンス・互換修正差分。
- `docs/`: 方法・注意点。`evidence/`: 新しい小規模検証の記録。
- リポジトリ直下 `.deps/fim/`: 固定版FIM・元AT・MATLABデータ（Git対象外）。
- `results/fim/comparison/` と `results/fim/stuck/`: 新規実行ごとのモデル・入力・波形・ログ（Git対象外）。

旧RPM・旧トルク比の結果、旧10故障コード、旧予備実験専用ランナーは現行構成から除いた。
Git管理済みの内容は履歴から復元できる。Mac上の退避先は
`/Users/harry/Documents/MATLAB/FIM-retired-20260926/`。
旧結果は新実験に混ぜない。旧予備実験の中断した試行を未発見として数えない。

## 準備・実行（リポジトリ直下）

MATLAB R2026a・Simulink・Stateflow、`.venv-falsify`、`s-taliro/dp_taliro` MEXが必要。
Ψ-TaLiRo用Pythonは既存 `../FIM/.venv-psy-arch/bin/python` を再利用する。仮想環境は移動しない。
依存定義は `dependencies/requirements-psy.txt`、取得元commitは `versions.json`。
固定版FIM/ATの初回取得（既存なら全ハッシュを照合し、上書きしない）:

```sh
python3 experiments/fim/dependencies/prepare.py --model-data /path/to/sldemo_autotrans_data.mat
```

オフラインでは `--fim-source /path/to/fimtool --arch-source /path/to/ARCH-COMP` を追加。
MATLABデータはライセンスのある付属例から取得し、Gitへ再配布しない。

```sh
.venv-falsify/bin/python -m unittest discover -s experiments/fim/tests -p 'test_*.py'
.venv-falsify/bin/python experiments/fim/python/run_stuck_preliminary.py prepare results/fim/stuck/NEW_NAME
.venv-falsify/bin/python experiments/fim/python/run_stuck_preliminary.py run results/fim/stuck/NEW_NAME
.venv-falsify/bin/python experiments/fim/python/run_torque_campaign.py prepare results/fim/comparison/NEW_NAME
.venv-falsify/bin/python experiments/fim/python/run_torque_campaign.py smoke results/fim/comparison/NEW_NAME
.venv-falsify/bin/python experiments/fim/python/launch_torque_campaign.py results/fim/comparison/NEW_NAME
```

`prepare` は既存フォルダへの上書きを拒否する。
`smoke` は正常128入力、全手法の学習開始、5故障の独立再実行を確認し、本実験には含めない。
`launch` は検査PASS後のみ開始し、アイドルスリープを抑止する（蓋閉じ・手動スリープは防がない）。
予備・本実験は共通ロックで同時実行を防ぐ。別の重い処理は実時間比較に影響する。

進捗は `status.json` と `trials/*/candidates.jsonl`。集計は次で再生成できる:

```sh
.venv-falsify/bin/python experiments/fim/python/summarize_torque_campaign.py results/fim/comparison/NEW_NAME
```

途中停止は実行フォルダに空ファイル `STOP_AFTER_TRIAL` を置くと、現在の1試行が終わってから停止する。
途中の試行がある場合は自動リトライしない。コード・条件・モデルは毎試行ハッシュ照合し、変化があれば停止する。

# トルク比低下と加速性能の予備実験

## 対象と目的

ARCHモデル `Autotrans_shift` の `Transmission/TorqueConverter/TorqueRatio` 出力に
FIMの `Bias/Offset` を挿入し、`Turbine` の入力2へ接続します。
`Turbine` の入力1はエンジン側トルクなので、宛先ブロック名だけで選ばず、
送信元 `TorqueRatio` を指定して1本だけに注入します。
FIMの `FISingle` による挿入と `FCSingle` による有効化を使用し、独自の加算ブロックで代用しません。

トルクコンバーターはマスク付きサブシステムです。従来のFIMの探索では内部の線が列挙されず、
注入0件になることを実行時に確認しました。
`dependencies/fim-masked-subsystems.patch` は `FISingle.m` の探索4か所へ
`LookUnderMasks='all'` を加えます。既存の互換修正版を実行フォルダへコピーした後にだけ適用し、
上流FIMや共有インストールは変更しません。注入先の完全一致と件数・接続ポートの検査を維持します。

モデルごとの故障は1個です。B00は正常、T01/T02/T03はトルク比をそれぞれ
0.02/0.05/0.10だけ減らします。固定値の減算であり2%/5%/10%ではありません。
5秒から30秒まで有効です。トルク比の誤りの抽象モデルであり、実機の油圧・損傷機構の同定ではありません。

## 条件

- MATLAB R2026a、ソルバーode5、固定刻み0.01秒、計算時間30秒。
- アクセルの変更は5秒ごと、区分定数（ZOH）。ブレーキは0。
- 初期状態、エンジン回転数制限、ギア比表は元モデルを保持。
- 元のARCHモデルとFalsify coreは変更せず、新規モデルを生成。
- この予備実験では探索ツール、乱数、学習を使わない。

| 入力 | 0–5秒 | 5–10秒 | 10–15秒 | 15–20秒 | 20–25秒 | 25–30秒 |
|---|---:|---:|---:|---:|---:|---:|
| A | 60 | 60 | 60 | 60 | 60 | 60 |
| B | 80 | 80 | 80 | 80 | 80 | 80 |
| C | 100 | 100 | 100 | 100 | 100 | 100 |
| D | 60 | 60 | 60 | 100 | 100 | 100 |
| E | 100 | 100 | 100 | 60 | 60 | 60 |
| F | 80 | 80 | 100 | 100 | 80 | 80 |

数字はアクセル開度%。30秒の入力値は25秒の値を保持し、新しい制御ステップとして数えません。
一定加速、踏み増し、戻し、一時的な踏み増しの基本挙動を比較するための6入力です。
入力範囲60～100、ブレーキ0の全波形を網羅するものではありません。

## STL要件と選定順序

1. `G_[0,30](gear >= 1 AND gear <= 4)`。等号を含みます。
2. 全保存時刻でgearが集合 `{1,2,3,4}` に属することを別途検査します。
   範囲要件だけでは2.5を除外できません。ギア信号に線形補間・丸め・クリップはしません。
3. 加速要件は `F_[0,20](speed_mph >= V)`。20秒を含む期限までに車速Vへ一度到達することです。
   瞬間加速度の要件ではなく、到達時間で測る加速性能の要件です。

期限20秒、余裕1 mph、丸め単位1 mphは故障評価前に設定します。
正常6波形について20秒までの最大車速を求め、その最小値から1 mphを引き、
1 mph単位で切り下げた値をVとします。
`V = floor(min_i(max_{0<=t<=20} speed_i(t)) - 1)`。
正常側だけで `target.json` に凍結してから故障側を実行します。
これは研究用に構成した要件で、実車の認証基準や全入力での安全性証明ではありません。
本評価では追加の正常入力と未使用の入力群で妥当性を検証し、条件を事前固定する必要があります。

加速ロバストネスは `max(speed_[0,20])-V` (mph)。負なら違反、0は境界を含む充足です。
ギアロバストネスは `min(gear-1,4-gear)` の全時刻の最小値です。
1速・4速で0になるため、加速の探索指標と最小値で合成しません。
両STL要件を `dp_taliro` でも独立に評価し、解析式との一致を検査します。
離散ギア検査は追加のBoolean検査です。NaN、Inf、途中停止、シミュレーション失敗を反例とは数えません。

## 実行

Falsifyリポジトリ直下のMATLABで:

```matlab
addpath('experiments/fim'); setup_fim();
test_fim_torque_spec();
runDirectory = run_fim_torque_acceleration('all');
```

段階ごとに実行する場合:

```matlab
runDirectory = run_fim_torque_acceleration('prepare');
run_fim_torque_acceleration('baseline', runDirectory);
run_fim_torque_acceleration('faults', runDirectory);
run_fim_torque_acceleration('report', runDirectory);
```

設定または実行コードを変更したら、新しいrunを作ります。以前の結果は上書きしません。

独立監査（既存のFalsify環境のNumPy/SciPyを使用）:

```sh
.venv-falsify/bin/python experiments/fim/tests/test_torque_acceleration.py
.venv-falsify/bin/python experiments/fim/python/audit_torque_acceleration.py RUN_DIRECTORY --output RUN_DIRECTORY/audit.json
```

## 保存と確認

`results/fim/torque_acceleration/<run-id>/` に保存します。

- `manifest.json`、`protocol.mat`、`code_snapshot/`: 条件、上流commit、元モデルのSHA256、使用コード。
- `generation_T*/Configuration/`: 実際の `config.csv`、`faults.csv`、`enable.csv`。
- `generation_T*/fault_table/Fault_table.xls`: FIMが実際に挿入したブロックの記録。
- `models/`: 正常モデルと故障モデル。
- `inputs.csv`: 6入力の値と変更時刻、単位付き列。
- `target.json`: 正常結果だけから固定した加速要件。
- `traces/`: 24組の全波形CSVとMAT。1波形3001行、0.01秒間隔。
- `checks/`: 故障無効化で正常波形に戻ることの18回の追加シミュレーション。
- `summary.csv`: 入力別・故障別の判定、到達時間、車速差、内部信号検査。
- `audit.json`: 保存CSVから独立に再計算した監査結果。

比較対象は正常6回＋故障18回＝24回です。無効化確認18回は別枠で、合計42回です。
故障開始前の正常波形との一致、注入前後のトルク比差、
`turbine_torque = impeller_torque * torque_ratio_after` の成立も検査します。
時系列列 `TorqueRatioBefore` は**その故障モデル内の**注入直前の値です。
故障後にはモデルの状態が変わるため、正常モデルのトルク比と同じとは限りません。
`FirstReachSeconds` がNaNなら30秒以内に未到達です。0秒とは異なります。
トルク列は上流モデルのネイティブ単位を保持し、未確認のSI単位へ読み替えません。

確認済みの24波形CSVと条件・集計は `evidence/` にGit保存します。
ライセンス付きモデルデータと生成モデルはGitへ再配布せず、run内と再生成手順で確認します。

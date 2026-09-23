"""Audit every saved candidate and build the five-method preliminary report."""
import argparse
import csv
import json
from pathlib import Path
import numpy as np
from scipy.io import loadmat
from audit_fim_at import audit_pair, rows

ALGORITHMS = ['RAND', 'ACER', 'A3C', 'DDQN', 'PSY_ConBOLS']
CASES = ['B00']+[f'F{i:02}' for i in range(1,11)]
SEEDS = [101,202,303]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    root = args.run.resolve()
    catalog = {r['ID']: r for r in rows(root/'fault_catalog.csv')}
    results = rows(root/'experiment2.csv')+rows(root/'additional_rl10_v2'/'experiment2.csv')
    psy = [json.loads(p.read_text()) for p in sorted((root/'additional_psy10').glob('*_PSY_ConBOLS_*.json'))]
    results += psy
    assert len(results) == 165, f'Incomplete: {len(results)} / 165 searches'
    assert {(r['Case'],r['Algorithm'],int(r['Seed'])) for r in results} == {
        (c,a,s) for c in CASES for a in ALGORITHMS for s in SEEDS}
    candidate_count, max_replay, max_monitor = 0, 0., 0.
    counts = {a:0 for a in ALGORITHMS}
    for row in results:
        folder = Path(row['CandidateDirectory']).resolve()
        assert root in folder.parents
        files = sorted(folder.glob('episode_*.mat'))
        assert len(files) == int(row['Episodes']) <= 10
        robustness = []
        if row['Algorithm'] == 'PSY_ConBOLS':
            history = json.loads((folder/'history.json').read_text())
            assert len(history) == len(files)
        for i, file in enumerate(files):
            data = loadmat(file, simplify_cells=True)
            rho = audit_pair(data['trace'],data['normal'],row['Case'],catalog)
            assert np.array_equal(data['u'],data['trace']['U'])
            robustness.append(rho)
            if row['Algorithm'] == 'PSY_ConBOLS':
                item = history[i]
                assert Path(item['CandidateFile']).resolve() == file
                assert abs(item['Rho']-rho) < 1e-9
                assert abs(item['MonitorRho']-rho) < 1e-9
                expected = np.asarray(data['trace']['ClauseMargins'])/[3000,3000,1.5,1.5]
                actual = [item['ClauseRho'][str(j)] for j in range(4)]
                np.testing.assert_allclose(actual,expected,rtol=0,atol=1e-9)
                max_monitor = max(max_monitor, item['MonitorError'])
            else:
                error = float(data['err'])
                assert error < 1e-5
                max_replay = max(max_replay,error)
            candidate_count += 1
            counts[row['Algorithm']] += 1
        assert abs(min(robustness)-float(row['Rho'])) < 1e-9
        violated = min(robustness) < -1e-9
        assert int(row['Violated']) == violated
        if violated:
            assert robustness[-1] < -1e-9 and all(r>=0 for r in robustness[:-1])
        else:
            assert len(robustness) == 10
        if row['Algorithm'] == 'A3C':
            assert int(row['LearningUpdates']) > 0
        if row['Algorithm'] == 'DDQN':
            assert int(row['LearningUpdates']) == 0 and int(row['ReplayStartSize']) == 500
        if row['Algorithm'] == 'PSY_ConBOLS':
            assert row['AdaptiveEvaluations'] == 0
    lines = ['# FIM / AT: 5手法の予備比較（最大10候補、3 seeds）', '',
        'このMacのMATLAB R2026aで、同じFIMモデル・入力範囲・STL要件を使用した比較です。',
        '探索結果を見て故障値・要件・シードは変更していません。未発見は安全の証明ではありません。', '',
        '## 反例発見の結果', '',
        '| 手法 | 故障ケースでの成功 / 30探索 | 発見した故障種類 / 10 | 正常系の違反 / 3 | 候補総数（正常系含む） |',
        '|---|---:|---:|---:|---:|']
    for a in ALGORITHMS:
        selected = [r for r in results if r['Algorithm']==a]
        bad = [r for r in selected if int(r['Violated']) and r['Case']!='B00']
        baseline = sum(int(r['Violated']) for r in selected if r['Case']=='B00')
        lines.append(f"| {a} | {len(bad)} | {len({r['Case'] for r in bad})} | {baseline} | {counts[a]} |")
    lines += ['', '各セルは、同じ故障について3 seeds中何回反例を発見したかを表します。', '',
        '| ケース | RAND | ACER | A3C | DDQN | Ψ-TaLiRo / ConBO-LS |', '|---|---:|---:|---:|---:|---:|']
    for c in CASES:
        cells = [str(sum(int(r['Violated']) for r in results if r['Case']==c and r['Algorithm']==a))+'/3'
                 for a in ALGORITHMS]
        lines.append('| '+c+' | '+' | '.join(cells)+' |')
    lines += ['', '## この表から主張できる範囲', '',
        '- 最大10候補の**予備比較**であり、学習・最適化を十分に行った性能ランキングではありません。',
        '- DDQNは既存設定のreplay_start_size=500を保持。全探索が学習開始前（更新0回）で終了しています。',
        '- A3CはFalsify既存ドライバの単一ワーカー実行。各探索で実際のoptimizer更新を記録しています。',
        '- Ψ-TaLiRoは論文指定版のConBO-LSを呼び出していますが、100点の初期LHS設計の先頭最大10点で終了。Bayesian optimizationの適応探索回数は0です。',
        '- 同じseed番号でも各手法の乱数生成器・抽出法は異なり、同じ候補列という意味ではありません。',
        '- 正常系は全候補で同じ入力を再実行して確認。FalsifyではさらにRLラッパーと独立FIMモデルの波形を照合しています。',
        '- F01 / F09 / F10の未発見が、故障の不存在や全入力での充足を意味するわけではありません。特に内部トルクの故障は今回のRPM・gear出力範囲要件では捉えにくい対照例です。',
        '- wall-clock時間にはMATLAB呼び出し・再実行・モデル読込の異なる付帯コストが含まれ、直接の速度比較には用いません。', '',
        '## 再現性と監査', '',
        f'- 165探索・{candidate_count}候補を独立Python監査。入力制約、正常系、指定故障演算、STL値、早期停止、候補数すべてPASS。',
        f'- 全Falsify候補のwrapper/replay最大誤差: {max_replay:.12g}。',
        f'- 全Ψ候補のRTAMT/解析的述語距離の最大誤差: {max_monitor:.12g}。',
        '- RTAMTは既存132波形と8つの境界・最終時刻テストでも解析式と一致。',
        '- 接続確認用pilotと中断した追加実験（additional_rl10、additional_psy_pilot*）は保持していますが、集計から除外しています。',
        '- 正式な追加結果: additional_rl10_v2/experiment2.csv、additional_psy10/*_PSY_ConBOLS_*.json。',
        '- 各フォルダのprotocol、runtime、code_snapshot、全候補MATを保存。元のモデル・上流FIM・Falsify coreは変更していません。',
        '- ローカルFIMブランチ上の作業であり、pushしていません。', '',
        '## Ψ-TaLiRoとの対応', '',
        '[ARCH2025公式報告](https://easychair.org/publications/paper/xX5W/open)のConBO-LSを選択。',
        '報告が参照する[公式再現パッケージ](https://github.com/cpslab-asu/ARCH-Comp-2024-Repeatability)',
        'の固定ConBOコミット532c4cd、psy-taliro 1.0.0b9、RTAMT 0.3.5を使用。',
        'CUDA依存のGPラッパーをCPUへ移植し、本体の探索実装は変更していません。PART-Xは今回未実施です。',
        '原実験との違い: 今回のFIM要件・30秒・両入力5秒刻み・14変数・10候補・3 seeds。',
        '複数要件をすべて違反させるeliminationではなく、Falsifyと同じく連言の最初の反例で停止します。',
        'そのため、ARCH2025の表の数値を再現した結果ではありません。', '',
        '次の比較では全手法の予算を共通に増やし、DDQNの学習更新とConBO-LSの適応探索が実際に生じたか確認してください。']
    (root/'COMPARISON.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    fields = ['Case','Algorithm','Seed','Episodes','Rho','Violated','BaselineRho','Seconds','CandidateDirectory']
    with (root/'comparison_searches.csv').open('w',newline='',encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        writer.writeheader(); writer.writerows(results)
    print('\n'.join(lines[:13]))
    print(f'PASS: all {candidate_count} candidates audited; report: {root / "COMPARISON.md"}')


if __name__ == '__main__':
    main()

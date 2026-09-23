"""Independent numerical audit of direct MATLAB RPM-offset calibration.

No search algorithms. Reads complete saved raw traces and input manifests,
then writes compact CSV/JSON/Markdown evidence in the NEW calibration run.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from scipy.io import loadmat

TOL = 1e-9


def critical_offset(t, y):
    t, y = np.asarray(t).reshape(-1), np.asarray(y)
    assert len(t) == len(y) and np.isfinite(y).all()
    return 6001.0 - float(y[t >= 5 - 1e-10, 0].max())


def robustness(y):
    y = np.asarray(y)
    assert np.isfinite(y).all()
    return float(min((y[:, 0].min()-599)/3000, (6001-y[:, 0].max())/3000,
                     (y[:, 2].min()-.5)/1.5, (4.5-y[:, 2].max())/1.5))


def choose_offset(critical, cfg):
    return max(cfg['offset_min'], math.ceil((min(critical)+cfg['recommendation_clearance_rpm']) /
                                          cfg['recommendation_step_rpm']) * cfg['recommendation_step_rpm'])


def table(path):
    with path.open(newline='', encoding='utf-8-sig') as handle:
        return list(csv.DictReader(handle))


def check_trace(trace):
    t, y, u = np.asarray(trace['T']).reshape(-1), np.asarray(trace['Y']), np.asarray(trace['U'])
    np.testing.assert_allclose(t, np.arange(3001)/100, rtol=0, atol=1e-10)
    assert y.shape == (3001, 3) and u.shape == (7, 3)
    np.testing.assert_array_equal(u[:, 0], np.arange(0, 31, 5))
    assert np.isfinite(y).all() and np.isfinite(u).all()
    assert (u[:, 1:] >= 0).all() and (u[:, 1:] <= [100, 325]).all()
    rho = robustness(y)
    assert abs(rho-float(trace['Rho'])) < 1e-9
    return t, y, u, rho


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    args = parser.parse_args()
    root = args.run.resolve()
    protocol = json.loads((root/'protocol.json').read_text())
    cfg = protocol['Config']
    declared = {r['ID']: r for r in json.loads((root/'inputs.json').read_text())}
    summary = json.loads((root/'summary.json').read_text())
    recorded_thresholds = {r['Input']: r for r in table(root/'thresholds.csv')}
    assert set(recorded_thresholds) == set(declared)
    baselines, critical, legacy = {}, {}, []
    raw_hashes = {}
    for path in sorted((root/'baseline').glob('*.mat')):
        raw_hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
        tr = loadmat(path, simplify_cells=True)['trace']
        t, y, u, rho = check_trace(tr)
        assert rho > TOL
        key = path.stem
        np.testing.assert_array_equal(u, declared[key]['U'])
        c = critical_offset(t, y)
        assert abs(c-float(recorded_thresholds[key]['CriticalOffsetRPM'])) < 1e-8
        if declared[key]['Group'] == 'legacy12':
            legacy.append(key)
            original = Path(protocol['PreviousRun'])/'exp1'/f'B00_{key}.mat'
            assert hashlib.sha256(original.read_bytes()).hexdigest() == declared[key]['SourceSHA256']
            old = loadmat(original, simplify_cells=True)['trace']
            np.testing.assert_array_equal(old['U'], u)
            np.testing.assert_allclose(old['Y'], y, rtol=0, atol=1e-7)
        baselines[key] = (t, y, u)
        critical[key] = c
    assert len(legacy) == 12 and len(baselines) == protocol['InputCount'] == len(declared)
    unique_inputs = {np.asarray(row['U']).tobytes() for row in declared.values()}
    assert len(unique_inputs) == len(declared), 'Duplicate input weighting'
    extra = sorted(set(critical)-set(legacy))
    recommendation = choose_offset(list(critical.values()), cfg)
    assert recommendation == summary['RecommendedOffsetRPM'] <= cfg['offset_max']
    counts = lambda ids, offset: sum(offset > critical[key] + 3000*TOL for key in ids)
    assert counts(legacy, 500) == 0 and counts(legacy, 1500) == 4
    for row in table(root/'offset_curve.csv'):
        offset = float(row['OffsetRPM'])
        assert counts(legacy, offset) == int(row['LegacyViolations'])
        assert counts(extra, offset) == int(row['AdditionalViolations'])
        assert counts(critical, offset) == int(row['TotalViolations'])
    for ids, label in [(legacy, 'Legacy'), (extra, 'Additional')]:
        assert counts(ids, recommendation) == summary[label+'ViolationsAtRecommendation']
    rows = table(root/'validation.csv')
    files = sorted((root/'validation').glob('V*.mat'))
    assert len(rows) == len(files) == summary['ActualFIMChecks']
    maximum_error, maximum_injection = 0.0, 0.0
    checked = set()
    for path, row in zip(files, rows):
        raw_hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
        data = loadmat(path, simplify_cells=True)
        tr = data['trace']; offset = float(data['offset']); key = data['input']['ID']
        assert row['Input'] == key and abs(float(row['OffsetRPM'])-offset) < 1e-9
        t, y, u, rho = check_trace(tr)
        bt, by, bu = baselines[key]
        np.testing.assert_array_equal(t, bt); np.testing.assert_array_equal(u, bu)
        expected = by.copy(); expected[t >= 5-1e-10, 0] += offset
        error = float(np.abs(expected-y).max()); maximum_error = max(maximum_error, error)
        assert error < 1e-7
        logged = tr['Injected']
        expected_signal = np.asarray(logged['Before']) + offset*(np.asarray(logged['T']) >= 5-1e-10)
        injection_error = float(np.abs(expected_signal-logged['After']).max())
        maximum_injection = max(maximum_injection, injection_error)
        assert injection_error < 1e-7
        assert (rho < -TOL) == bool(int(row['Violated'])) == (offset > critical[key]+3000*TOL)
        assert (abs(rho) <= TOL) == bool(int(row['Boundary']))
        assert abs(float(row['Rho'])-rho) < 1e-9
        assert float(row['MonitorError']) < 1e-9
        checked.add((key, offset))
    assert all((key, recommendation) in checked for key in declared)
    assert all((key, offset) in checked for key in legacy for offset in (500.0, 1500.0))
    off = loadmat(root/'fault_off.mat', simplify_cells=True)
    _, oy, _, _ = check_trace(off['off'])
    np.testing.assert_allclose(oy, baselines[off['input']['ID']][1], rtol=0, atol=1e-7)
    evidence = dict(Status='PASS', BaselineInputs=len(baselines), ActualFaultSimulations=len(files),
                    RecommendedOffsetRPM=recommendation, MaximumWaveformError=maximum_error,
                    MaximumInjectionError=maximum_injection, RawSHA256=raw_hashes,
                    Scope='All saved traces audited. Calibration sample, not a probability estimate or proof.')
    (root/'audit.json').write_text(json.dumps(evidence, indent=2)+'\n')
    compact = dict(summary)
    compact['CalibrationRun'] = root.name
    compact['Thresholds'] = [dict(Input=k, Group=declared[k]['Group'],
                                 Description=declared[k]['Description'], CriticalOffsetRPM=critical[k])
                             for k in sorted(critical, key=critical.get)]
    compact['Audit'] = {k: v for k, v in evidence.items() if k != 'RawSHA256'}
    (root/'reviewed_results.json').write_text(json.dumps(compact, indent=2, ensure_ascii=False)+'\n')
    lines = ['# RPM正加算の準備実験', '',
             f'暫定推奨: **+{recommendation:g} rpm**。設定した固定入力群で反例を残す小さい加算量として選定。',
             '探索手法の優劣や学習効果を最大化する最適値という意味ではありません。', '',
             f'- 従来12入力の最初の境界: +{min(critical[k] for k in legacy):.9f} rpm。',
             f'- 追加{len(extra)}入力を含む全{len(baselines)}入力の最初の境界: +{min(critical.values()):.9f} rpm。',
             f'- 推奨値で違反: 従来 {counts(legacy,recommendation)}/12、追加 {counts(extra,recommendation)}/{len(extra)}。',
             f'- FIMで実行した確認: {len(files)}件、別途OFF確認1件。正常系 {len(baselines)}件。',
             f'- 予測波形とFIMの最大差: {maximum_error:.3g}。独立監査: PASS。', '',
             '## 従来12入力の境界', '', '| 入力 | 5秒以降の最大RPM | 加算値の境界 |', '|---|---:|---:|']
    for key in sorted(legacy):
        lines.append(f'| {key} | {6001-critical[key]:.6f} | {critical[key]:.6f} |')
    lines += ['', '## 解釈', '',
              '- 境界そのものではロバストネス0。許容誤差より明確に負の場合だけ違反に数えます。',
              '- 1rpm刻みの全曲線は正常波形からの解析計算です。全加算値をSimulinkで総当たりしたものではありません。',
              '- 推奨値は全固定入力で実際のFIMブロックを用いて再実行し、境界の両側と等号も代表入力で確認しました。',
              '- 全入力は調整用です。割合をランダム入力の違反確率とは解釈できません。将来の本評価には別のseed・入力を使います。',
              '- 出力RPMに加算する故障であり、エンジン内部状態には加算していません。',
              '- RAND/ACER/A3C/DDQN/Ψ-TaLiRoはこの調査では実行していません。',
              '- 検証はode5、0.01秒刻み、30秒、故障開始5秒の記録波形についての結果で、全入力・連続時間の形式証明ではありません。', '',
              '根拠: `protocol.json`, `inputs.json`, `thresholds.csv`, `offset_curve.csv`, `validation.csv`, `audit.json`。']
    (root/'RESULTS.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({k:v for k,v in evidence.items() if k != 'RawSHA256'}, indent=2))
    print('REPORT:', root/'RESULTS.md')


if __name__ == '__main__':
    main()

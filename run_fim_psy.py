"""ARCH-pinned Psi-TaLiRo/ConBO-LS on the existing FIM-generated AT plants.

The common budget counts candidate inputs, excluding baseline verification.
Below 100 candidates this is ONLY a prefix of ConBO-LS's 100-point LHS design.
The first negative conjunction stops the run, including during initialization.
"""
import argparse
import hashlib
import importlib.metadata
import io
import json
import random
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import torch
from scipy.io import loadmat
from lsemibo.coreAlgorithm import LSemiBOOptimizer
from lsemibo.coreAlgorithm.specification import Requirement
from lsemibo.classifierInterface import InternalClassifier
from staliro.core.model import Model, Trace, ExtraResult
from staliro.options import Options, SignalOptions
from staliro.signals import piecewise_constant
from staliro.staliro import staliro

from fim_psy_gpr import ExternalGPRCPU

TOL = 1e-9
NAMES = ('rpmlo', 'rpmhi', 'gearlo', 'gearhi')
FORMULAS = [f'G[0,30] ({name} > 0)' for name in NAMES]
MAPPING = {name: (list(range(14)), i) for i, name in enumerate(NAMES)}


def margins(y):
    y = np.asarray(y, dtype=float)
    return np.column_stack(((y[:, 0]-599)/3000, (6001-y[:, 0])/3000,
                            (y[:, 2]-.5)/1.5, (4.5-y[:, 2])/1.5))


def save_json(path, data):
    path = Path(path)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False)+'\n')
    temporary.replace(path)


class SearchComplete(Exception):
    """Expected first-counterexample / hard-budget termination, not a tool error."""


class AuditedRequirement(Requirement):
    def __init__(self, model):
        super().__init__(14, FORMULAS, MAPPING)
        self.model = model

    def evaluate(self, states, times):
        result = super().evaluate(states, times)
        expected = np.min(np.asarray(states), axis=0)
        assert len(result) == 4, 'A new candidate was evaluated after a counterexample'
        error = max(abs(result[i]-expected[i]) for i in range(4))
        assert error < TOL, f'RTAMT/analytic clause mismatch: {error}'
        rho = float(min(result.values()))
        item = self.model.history[-1]
        assert abs(rho-item['Rho']) < TOL
        item['MonitorRho'] = rho
        item['MonitorError'] = float(error)
        item['ClauseRho'] = {str(k): float(v) for k, v in result.items()}
        save_json(self.model.folder/'history.json', self.model.history)
        return result


class FIMModel(Model):
    def __init__(self, engine, run, case, folder, budget):
        self.engine, self.run, self.case = engine, run, case
        self.folder, self.budget = folder, budget
        self.history = []

    def simulate(self, inputs, interval):
        import matlab
        if self.history and self.history[-1]['Rho'] < -TOL:
            raise SearchComplete('counterexample')
        if len(self.history) >= self.budget:
            raise SearchComplete('budget')
        assert interval.lower == 0 and interval.upper == 30
        times = np.arange(0., 31., 5.)
        u = np.column_stack([times]+[
            [signal.at_time(t) for t in times] for signal in inputs.signals])
        assert u.shape == (7, 3) and np.isfinite(u).all()
        assert (u[:, 1:] >= 0).all() and (u[:, 1:] <= [100, 325]).all()
        episode = len(self.history)+1
        file = self.folder/f'episode_{episode:03d}.mat'
        capture = io.StringIO()
        started = time.perf_counter()
        self.engine.fim_at_external(str(self.run), self.case,
            matlab.double(u.tolist()), str(file), nargout=0, stdout=capture, stderr=capture)
        data = loadmat(file, simplify_cells=True)
        trace, normal = data['trace'], data['normal']
        y = np.asarray(trace['Y'], dtype=float)
        rho = float(margins(y).min())
        assert abs(rho-trace['Rho']) < TOL
        assert normal['Rho'] > 0 and trace['InjectionError'] < 1e-7
        assert np.allclose(data['u'], u, rtol=0, atol=1e-12)
        self.history.append(dict(Episode=episode, Rho=rho,
            BaselineRho=float(normal['Rho']), CandidateFile=str(file),
            SimulationAndBaselineSeconds=time.perf_counter()-started,
            Phase='initial_LHS' if episode <= 100 else 'Bayesian_optimization'))
        print(f'{self.case} candidate {episode}: rho={rho:.10g}', flush=True)
        return ExtraResult(Trace(trace['T'], margins(y)), str(file))


def make_optimizer(seed, budget):
    return LSemiBOOptimizer(method='falsification', is_budget=100,
        max_budget=max(100, budget), cs_budget=1000, top_k=3,
        classified_sample_bias=.8, tf_dim=14, R=10, M=500,
        gpr_model=ExternalGPRCPU(), classifier_model=InternalClassifier(),
        is_type='lhs_sampling', cs_type='lhs_sampling', pi_type='lhs_sampling', seed=seed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run', type=Path)
    parser.add_argument('--budget', type=int, default=10)
    parser.add_argument('--folder', default='additional_psy10')
    parser.add_argument('--cases', nargs='+', default=['B00']+[f'F{i:02}' for i in range(1,11)])
    parser.add_argument('--seeds', type=int, nargs='+', default=[101,202,303])
    args = parser.parse_args()
    assert args.budget > 0
    assert args.folder.startswith('additional_') and '/' not in args.folder and '..' not in args.folder
    assert set(args.cases) <= {'B00'} | {f'F{i:02}' for i in range(1,11)}
    repo = Path(__file__).resolve().parent
    run = args.run.resolve()
    assert (run/'protocol.mat').is_file()
    root = run/args.folder
    root.mkdir(exist_ok=True)
    protocol = dict(Budget=args.budget, Cases=args.cases, Seeds=args.seeds,
        InitialDesignSize=100, Formulas=FORMULAS, SignalTimes=list(range(0,31,5)),
        Bounds=[[0,100],[0,325]], Monitor='RTAMT dense; normalized margins',
        StopRule='first conjunction violation, including initial design',
        ConBOCommit='532c4cd033dc373bf81b6505ea3389e7a4860b22',
        RepeatabilityCommit='537de5951c6a2eabb6f4aca9739a7b0a15b95824',
        Scope='FIM profile comparison, NOT original ARCH2025 result reproduction',
        GPPort='CPU device; original Matern kernel and unscaled Y fit retained')
    if (root/'protocol.json').exists():
        assert json.loads((root/'protocol.json').read_text()) == protocol
    else:
        save_json(root/'protocol.json', protocol)
    snapshot = root/'code_snapshot'
    snapshot.mkdir(exist_ok=True)
    for name in ['run_fim_psy.py','fim_psy_gpr.py','fim_at_external.m',
                 'run_fim_at_experiments.m','fim_at_spec.m']:
        target = snapshot/name
        if target.exists():
            assert target.read_bytes() == (repo/name).read_bytes(), f'Code changed: {name}'
        else:
            shutil.copy2(repo/name, target)
    versions = {p: importlib.metadata.version(p) for p in
                ['psy-taliro','LSemiBO','rtamt','numpy','scipy','torch','botorch','gpytorch','matlabengine']}
    import lsemibo.coreAlgorithm.staliroIntegration as implementation
    versions['OptimizerSHA256'] = hashlib.sha256(Path(implementation.__file__).read_bytes()).hexdigest()
    versions['Python'] = sys.version
    save_json(root/'runtime.json', versions)
    (root/'requirements-lock.txt').write_text(subprocess.check_output(
        [sys.executable,'-m','pip','freeze'], text=True))
    import matlab.engine
    engine = matlab.engine.start_matlab('-nodesktop -nosplash')
    engine.addpath(str(repo), nargout=0)
    torch.set_num_threads(1)
    try:
        for case in args.cases:
            for seed in args.seeds:
                tag = f'{case}_PSY_ConBOLS_{seed}'
                result_file = root/f'{tag}.json'
                if result_file.exists():
                    print('RESUME skip', tag, flush=True)
                    continue
                # New attempt prevents accidental reuse of an incomplete candidate sequence.
                import tempfile
                folder = Path(tempfile.mkdtemp(prefix=tag+'_', dir=root))
                np.random.seed(seed); random.seed(seed); torch.manual_seed(seed)
                model = FIMModel(engine, run, case, folder, args.budget)
                spec = AuditedRequirement(model)
                optimizer = make_optimizer(seed, args.budget)
                signals = [SignalOptions(control_points=[bounds]*7,
                    signal_times=np.arange(0.,31.,5.).tolist(), factory=piecewise_constant)
                    for bounds in [(0,100),(0,325)]]
                options = Options(runs=1, iterations=args.budget, interval=(0,30),
                                  signals=signals, seed=seed)
                start = time.perf_counter()
                try:
                    staliro(model, spec, optimizer, options)
                except SearchComplete:
                    pass
                elapsed = time.perf_counter()-start
                history = model.history
                assert history and len(history) <= args.budget
                assert all('MonitorRho' in h for h in history)
                best = min(history, key=lambda h: h['Rho'])
                assert best['Rho'] < -TOL or len(history) == args.budget
                result = dict(Case=case, Algorithm='PSY_ConBOLS', Seed=seed,
                    Episodes=len(history), Seconds=elapsed, Rho=best['Rho'],
                    Violated=best['Rho'] < -TOL, BaselineRho=best['BaselineRho'],
                    MaxEpisodes=args.budget, CandidateDirectory=str(folder),
                    BestCandidateFile=best['CandidateFile'],
                    AdaptiveEvaluations=max(0,len(history)-100),
                    MonitorMaxError=max(h['MonitorError'] for h in history))
                save_json(result_file, result)
                print('COMPLETE', tag, result, flush=True)
    finally:
        engine.quit()


if __name__ == '__main__':
    main()

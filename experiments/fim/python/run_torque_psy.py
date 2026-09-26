"""Pinned Psi-TaLiRo/ConBO, single acceleration property, CPU, fresh trial.

Six optimizer coordinates encode six held throttle values (brake is fixed 0).
This is the installed ConBO implementation's single-requirement EI path,
not its multi-conjunct elimination benchmark. Initial 100 LHS count in budget.
"""
import argparse
import hashlib
import importlib.metadata
import io
import json
from pathlib import Path
import random
import shutil
import sys
import time

import numpy as np
import torch
from scipy.io import loadmat
from lsemibo.coreAlgorithm import LSemiBOOptimizer
from lsemibo.coreAlgorithm.specification import Requirement
from lsemibo.classifierInterface import InternalClassifier
from staliro.core.model import Model, Trace, ExtraResult
from staliro.options import Options
from staliro.staliro import staliro
from fim_psy_gpr import ExternalGPRCPU
from run_torque_campaign import write_json


class CountedGPR(ExternalGPRCPU):
    fits = 0

    def fit_gpr(self, X, Y):
        super().fit_gpr(X,Y)
        CountedGPR.fits += 1


class SearchComplete(Exception):
    pass


class AuditedRequirement(Requirement):
    def __init__(self, model):
        super().__init__(6,['F[0,20] (accel >= 0)'],{'accel':(list(range(6)),0)})
        self.model=model

    def evaluate(self, states, times):
        result=super().evaluate(states,times)
        assert len(result)==1
        rho=float(result[0])
        item=self.model.history[-1]
        error=abs(item['Rho']-rho)
        assert error<1e-9, f'RTAMT/common monitor mismatch: {error}'
        item['MonitorRho']=rho
        item['MonitorError']=error
        item['SearchSeconds']=time.perf_counter()-self.model.start-self.model.verification_seconds
        with (self.model.folder/'candidates.jsonl').open('a') as output:
            output.write(json.dumps(item,allow_nan=False)+'\n')
        if rho<0:
            assert item['Verification']['ValidCounterexample']
            # Stop immediately even inside the precomputed 100-point LHS loop.
            raise SearchComplete('verified counterexample')
        return result


class TorqueModel(Model):
    def __init__(self, engine, campaign, case, budget, folder):
        self.engine,self.campaign,self.case,self.budget,self.folder=engine,campaign,case,budget,folder
        self.history=[]
        self.verification_seconds=0.
        self.verification_simulations=0
        self.best=float('inf')
        self.start=None

    def simulate(self, inputs, interval):
        import matlab
        if len(self.history)>=self.budget:
            raise SearchComplete('budget')
        assert interval.lower==0 and interval.upper==30
        throttle=np.asarray(inputs.static,dtype=float)
        assert throttle.shape==(6,) and np.isfinite(throttle).all()
        assert (throttle>=60).all() and (throttle<=100).all()
        u=np.column_stack((np.arange(0.,31.,5.),np.r_[throttle,throttle[-1]],np.zeros(7)))
        episode=len(self.history)+1
        file=self.folder/'latest.mat'
        capture=io.StringIO()
        self.engine.fim_comparison_plant(str(self.campaign),self.case,matlab.double(u.tolist()),
            str(file),nargout=0,stdout=capture,stderr=capture)
        trace=loadmat(file,simplify_cells=True)['trace']
        y=np.asarray(trace['Y'],dtype=float); t=np.asarray(trace['T'],dtype=float)
        rho=float(trace['Rho'])
        expected=float((y[t<=20+1e-10,1].max()-95)/80)
        assert abs(rho-expected)<1e-9 and trace['Monitor']['GearPass']
        item=dict(Episode=episode,Rho=rho,RhoMPH=rho*80,Throttle=throttle.tolist(),
                  GearPass=True,Phase='initial_LHS' if episode<=100 else 'single_property_EI',
                  Verification={})
        if episode==1 or rho<0:
            verification=self.engine.fim_comparison_verify(str(self.campaign),self.case,
                matlab.double(u.tolist()),matlab.double(y.tolist()),
                str(self.folder/f'verification_{episode:04d}'),stdout=capture,stderr=capture)
            verification={str(k):v for k,v in verification.items()}
            self.verification_seconds+=float(verification['Seconds'])
            self.verification_simulations+=int(verification['Simulations'])
            assert rho>=0 or verification['ValidCounterexample']
            item['Verification']=verification
        if rho<self.best:
            self.best=rho
            shutil.copy2(file,self.folder/'best.mat')
            np.savetxt(self.folder/'best-trace.csv',np.column_stack((t,y)),delimiter=',',
                       header='TimeSeconds,RPM,SpeedMPH,Gear',comments='',fmt='%.17g')
        self.history.append(item)
        print(f'{self.case} PSY input {episode}: rho={rho:.10g}, GP fits={CountedGPR.fits}',flush=True)
        return ExtraResult(Trace(t,((y[:,1]-95)/80).reshape(-1,1)),str(file))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign',type=Path); parser.add_argument('case')
    parser.add_argument('seed',type=int); parser.add_argument('budget',type=int)
    parser.add_argument('folder',type=Path)
    args=parser.parse_args()
    protocol=json.loads((args.campaign/'protocol.json').read_text())
    assert args.case in ['B00']+protocol['cases'], 'Unknown fault case'
    args.folder.mkdir(exist_ok=False)
    torch.set_num_threads(1)
    np.random.seed(args.seed); random.seed(args.seed); torch.manual_seed(args.seed)
    CountedGPR.fits=0
    import lsemibo.coreAlgorithm.staliroIntegration as implementation
    runtime={p:importlib.metadata.version(p) for p in
             ['psy-taliro','LSemiBO','rtamt','numpy','scipy','torch','botorch','gpytorch','matlabengine']}
    runtime['OptimizerSHA256']=hashlib.sha256(Path(implementation.__file__).read_bytes()).hexdigest()
    runtime['Python']=sys.version
    write_json(args.folder/'runtime.json',runtime)
    import matlab.engine
    engine=matlab.engine.start_matlab('-nodesktop -nosplash -singleCompThread')
    try:
        engine.addpath(str(Path(__file__).resolve().parents[1]),nargout=0)
        engine.setup_fim(nargout=0)
        model=TorqueModel(engine,args.campaign.resolve(),args.case,args.budget,args.folder)
        spec=AuditedRequirement(model)
        optimizer=LSemiBOOptimizer(method='falsification',is_budget=100,
            max_budget=max(100,args.budget),cs_budget=1000,top_k=3,classified_sample_bias=.8,
            tf_dim=6,R=10,M=500,gpr_model=CountedGPR(),classifier_model=InternalClassifier(),
            is_type='lhs_sampling',cs_type='lhs_sampling',pi_type='lhs_sampling',seed=args.seed)
        options=Options(runs=1,iterations=args.budget,interval=(0,30),
                        static_parameters=[(60,100)]*6,seed=args.seed)
        model.start=time.perf_counter()
        try:
            staliro(model,spec,optimizer,options)
        except SearchComplete:
            pass
        elapsed=time.perf_counter()-model.start-model.verification_seconds
        history=model.history
        assert history and all('MonitorRho' in h for h in history)
        assert model.best<0 or len(history)==args.budget
        result=dict(Case=args.case,Algorithm='PSY',Seed=args.seed,Episodes=len(history),
            Budget=args.budget,Violated=model.best<0,Rho=model.best,RhoMPH=model.best*80,
            SearchSeconds=elapsed,VerificationSeconds=model.verification_seconds,
            VerificationSimulations=model.verification_simulations,
            AdaptiveEvaluations=max(0,len(history)-100),GPFitCount=CountedGPR.fits,
            MonitorMaxError=max(h['MonitorError'] for h in history),Status='complete')
        write_json(args.folder/'result.json',result)
        print('COMPLETE',result,flush=True)
    finally:
        engine.quit()


if __name__=='__main__':
    main()

function result=fim_comparison_verify(campaign,caseID,u,referenceY,folder)
% Common out-of-budget replay. Never return baseline data to the optimizer.
started=tic;
fault=fim_comparison_plant(campaign,caseID,u);
normal=fim_comparison_plant(campaign,'B00',u);
error_=max(abs(fault.Y-referenceY),[],'all');
assert(error_<1e-5,'FIM:ReplayMismatch','Candidate/replay mismatch: %g',error_);
assert(normal.Monitor.Pass,'FIM:BaselineViolation','Normal model violates the frozen property; stop campaign.');
result=struct('ValidCounterexample',fault.Rho<0 && normal.Monitor.Pass, ...
    'FaultRho',fault.Rho,'NormalRho',normal.Rho,'ReplayError',error_, ...
    'Seconds',toc(started),'Simulations',2);
if isfield(fault,'Applied')
    disabled=fim_comparison_plant(campaign,caseID,u,'',false);
    result.DisabledReplayError=max(abs(disabled.Y-normal.Y),[],'all');
    assert(result.DisabledReplayError<1e-7,'FIM:DisabledMismatch','Disabled fault differs from normal.');
    result.Simulations=3;
    result.Seconds=toc(started);
end
if ~isempty(folder)
    if ~isfolder(folder), mkdir(folder); end
    if isfield(fault,'Applied')
        save(fullfile(folder,'verification.mat'),'fault','normal','disabled','result');
    else
        save(fullfile(folder,'verification.mat'),'fault','normal','result');
    end
    for data={fault,normal}
        tr=data{1};
        if isfield(tr,'Applied')
            values=[tr.T tr.Y tr.Command tr.Applied tr.Ratio tr.Gate];
            names={'TimeSeconds','RPM','SpeedMPH','Gear','CommandedGear','AppliedGear','GearRatio','FaultGate'};
        else
            values=[tr.T tr.Y tr.RatioBefore tr.RatioAfter];
            names={'TimeSeconds','RPM','SpeedMPH','Gear','RatioBefore','RatioAfter'};
        end
        tbl=array2table(values,'VariableNames',names);
        writetable(tbl,fullfile(folder,[tr.Case '.csv']));
    end
    writematrix(u,fullfile(folder,'input.csv'));
end
end

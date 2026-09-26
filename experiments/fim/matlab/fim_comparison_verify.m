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
if ~isempty(folder)
    if ~isfolder(folder), mkdir(folder); end
    save(fullfile(folder,'verification.mat'),'fault','normal','result');
    for data={fault,normal}
        tr=data{1};
        values=[tr.T tr.Y tr.RatioBefore tr.RatioAfter];
        tbl=array2table(values,'VariableNames',{'TimeSeconds','RPM','SpeedMPH','Gear','RatioBefore','RatioAfter'});
        writetable(tbl,fullfile(folder,[tr.Case '.csv']));
    end
    writematrix(u,fullfile(folder,'input.csv'));
end
end

function validate_fim_torque_baseline(campaign)
% Finite independent baseline screen, explicitly not a proof over all inputs.
inputs=readmatrix(fullfile(campaign,'baseline-inputs.csv'));
assert(isequal(size(inputs),[128 6]));
rows=zeros(128,10);
for k=1:128
    throttle=[inputs(k,:) inputs(k,end)]';
    trace=fim_comparison_plant(campaign,'B00',[(0:5:30)' throttle zeros(7,1)]);
    assert(trace.Monitor.Pass,'FIM:BaselineViolation','Baseline input %d violates the property.',k);
    rows(k,:)=[k inputs(k,:) trace.Rho trace.Monitor.GearPass trace.SimulationSeconds];
    if mod(k,16)==0, fprintf('BASELINE %d/128, rho=%g\n',k,trace.Rho); end
end
tbl=array2table(rows,'VariableNames',{'Input','Throttle0','Throttle5','Throttle10', ...
    'Throttle15','Throttle20','Throttle25','Rho','GearPass','SimulationSeconds'});
writetable(tbl,fullfile(campaign,'baseline-results.csv'));
fid=fopen(fullfile(campaign,'baseline-validation.json'),'w');
fprintf(fid,'%s\n',jsonencode(struct('Status','PASS','Inputs',128, ...
    'MinimumRho',min(rows(:,8)),'Scope','finite screen, not a universal proof'))); fclose(fid);
end

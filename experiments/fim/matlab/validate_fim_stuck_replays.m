function validate_fim_stuck_replays(campaign)
% Predeclared pilot witness I121, not a newly selected counterexample.
values=[66.80106059;67.03798059;78.61660628;85.05396942;63.70220212;75.38670708];
u=[(0:5:30)' [values;values(end)] zeros(7,1)];
normal=fim_comparison_plant(campaign,'B00',u);
assert(normal.Monitor.Pass);
catalog=readtable(fullfile(campaign,'fault_catalog.csv'),'TextType','string');
rows={};
for k=2:height(catalog)
    id=char(catalog.ID(k)); trace=fim_comparison_plant(campaign,id,u);
    pre=trace.T<catalog.Onset(k)-1e-10;
    before=max(abs(trace.Y(pre,:)-normal.Y(pre,:)),[],'all'); assert(before<1e-7);
    verification=fim_comparison_verify(campaign,id,u,trace.Y,fullfile(campaign,'replay-checks',id));
    if strcmp(id,'S03'), assert(trace.HeldSamples>0,'Pilot hold witness must affect internal gear.'); end
    rows{end+1}=struct('Case',id,'HeldSamples',trace.HeldSamples,'Rho',trace.Rho, ...
        'BeforeFaultError',before,'ReplayError',verification.ReplayError, ...
        'DisabledReplayError',verification.DisabledReplayError); %#ok<AGROW>
end
writetable(struct2table([rows{:}]),fullfile(campaign,'replay-checks.csv'));
fprintf('PASS: all 9 Stuck-at enabled/disabled replays.\n');
end

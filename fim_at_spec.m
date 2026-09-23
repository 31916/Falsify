function spec = fim_at_spec()
%FIM_AT_SPEC Separate invariant profile; does not replace ARCH benchmark data.
% Official Engine/Integrator clips RPM to [600,6000]. ShiftLogic assigns
% only gears 1..4. A 1 rpm / 0.5 gear margin avoids zero robustness at bounds.
% This is a structural model argument, NOT a formal reachability certificate.
spec.ID = 'FIM_AT_INVARIANT_V1';
spec.StopTime = 30;
spec.SampleTime = 5;
spec.InputRange = [0 100; 0 325];
spec.OutputRange = [0 6000; 0 160; 1 4]; % RPM, speed, gear; NOT clipping
spec.Formula = '[]_[0,30](rpmlo /\ rpmhi /\ gearlo /\ gearhi)';
names = {'rpmlo','rpmhi','gearlo','gearhi'};
A = [-1 0 0; 1 0 0; 0 0 -1; 0 0 1];
b = [-599;6001;-0.5;4.5];
for k = 1:4
    spec.Preds(k).str = names{k};
    spec.Preds(k).A = A(k,:);
    spec.Preds(k).b = b(k);
end
spec.Seeds = [101 202 303];
spec.Algorithms = {'RAND','ACER'};
spec.MaxEpisodes = 10;
spec.FaultTime = 5;
spec.Tolerance = 1e-9;
% Freeze these values before any simulations. One fault per mutant.
spec.Faults = table( ...
    compose('F%02d',(1:10)'), ...
    [repmat("NA",8,1);repmat("Transmission/TransmissionRatio",2,1)], ...
    [repmat("RPM",6,1);repmat("gear",2,1);repmat("Tout",2,1)], ...
    [repmat("Bias/Offset",4,1);"Negate";"Stuck-at 0";repmat("Bias/Offset",4,1)], ...
    [500;1500;-500;-1500;0;0;1;-1;10;100], ...
    'VariableNames',{'ID','Level','Destination','Type','Value'});
end

function test_fim_torque_spec()
% Boundary cases, temporal horizon, discrete gear and invalid numeric output.
paths=fim_paths(); addpath(fullfile(paths.Repo,'s-taliro','dp_taliro'));
s=fim_torque_spec(); suite=fim_torque_inputs(s);
assert(numel(suite)==6 && isequal(s.GearRange,[1 4]));
for k=1:6
    assert(isequal(suite(k).U(:,1),(0:5:30)') && all(suite(k).U(:,3)==0));
    assert(isequal(suite(k).U(1:6,2)',s.Throttle(k,:)));
    assert(isequal(suite(k).U(end,2:3),suite(k).U(end-1,2:3)));
end
t=(0:.01:30)'; target=struct('DeadlineSeconds',20,'TargetSpeedMPH',50,'Formula','<>_[0,20](fast)');
y=[1000*ones(size(t)) 50*ones(size(t)) ones(size(t))];
m=fim_torque_monitor(t,y,target,s); assert(m.Pass && m.GearRho==0 && m.AccelerationRhoMPH==0);
y(:,3)=4; m=fim_torque_monitor(t,y,target,s); assert(m.Pass && m.GearRho==0);
for gear=[0.999999 4.000001 0 5]
    y(:,3)=gear; m=fim_torque_monitor(t,y,target,s); assert(~m.GearPass && ~m.Pass);
end
y(:,3)=2.5; m=fim_torque_monitor(t,y,target,s); assert(m.GearRangePass && ~m.GearDiscretePass && ~m.Pass);
y(:,3)=1; y(:,2)=49; y(2001,2)=50;
m=fim_torque_monitor(t,y,target,s); assert(m.AccelerationPass && m.FirstReachSeconds==20);
y(2001,2)=49; y(2002,2)=50;
m=fim_torque_monitor(t,y,target,s); assert(~m.AccelerationPass && abs(m.FirstReachSeconds-20.01)<1e-10);
y(1,2)=NaN;
try, fim_torque_monitor(t,y,target,s); error('Test:ExpectedError','Expected nonfinite rejection.');
catch err, assert(strcmp(err.identifier,'FIM:Nonfinite')); end
fprintf('PASS: torque pilot inputs, inclusive gear bounds, discrete gears, closed deadline, nonfinite rejection.\n');
end

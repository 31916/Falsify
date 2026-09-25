function result = fim_torque_monitor(t, y, target, spec)
%FIM_TORQUE_MONITOR Independent properties; y order is RPM, speed_mph, gear.
% Closed predicates: rho=0 satisfies the inclusive range/arrival property.
% Exact gear membership is separate: a range alone would admit gear=2.5.
assert(iscolumn(t) && size(y,1)==numel(t) && size(y,2)==3);
assert(all(isfinite(t)) && all(isfinite(y),'all'), ...
    'FIM:Nonfinite','Nonfinite simulation output is an error, not a counterexample.');
assert(t(1)==0 && abs(t(end)-spec.StopTime)<1e-10 && all(diff(t)>0));
assert(target.DeadlineSeconds==spec.AccelerationDeadline);
window = t<=target.DeadlineSeconds+1e-10;
speed = y(:,2); gear = y(:,3);
result = struct();
result.AccelerationRhoMPH = max(speed(window))-target.TargetSpeedMPH;
result.AccelerationPass = result.AccelerationRhoMPH>=0;
result.GearRho = min([gear-spec.GearRange(1);spec.GearRange(2)-gear]);
result.GearRangePass = all(gear>=spec.GearRange(1) & gear<=spec.GearRange(2));
result.GearDiscretePass = all(ismember(gear,spec.GearValues));
result.GearPass = result.GearRangePass && result.GearDiscretePass;
result.Pass = result.AccelerationPass && result.GearPass;
first = find(speed>=target.TargetSpeedMPH,1);
result.FirstReachSeconds = NaN;
if ~isempty(first), result.FirstReachSeconds=t(first); end
result.PeakSpeedByDeadlineMPH = max(speed(window));
result.SpeedAtDeadlineMPH = speed(find(window,1,'last'));
result.SpeedAt30MPH = speed(end);
result.MinRPM = min(y(:,1)); result.MaxRPM = max(y(:,1));
result.MinGear = min(gear); result.MaxGear = max(gear);
% Cross-check STL against the existing Falsify monitor, without normalization.
p = struct('str','fast','A',[0 -1 0],'b',-target.TargetSpeedMPH);
rho = dp_taliro(target.Formula,p,y,t,[],[],[]);
result.AccelerationMonitorError = abs(rho-result.AccelerationRhoMPH);
p = struct('str',{'gearlo','gearhi'},'A',{[0 0 -1],[0 0 1]}, ...
    'b',{-spec.GearRange(1),spec.GearRange(2)});
rho = dp_taliro(spec.GearFormula,p,y,t,[],[],[]);
result.GearMonitorError = abs(rho-result.GearRho);
assert(result.AccelerationMonitorError<spec.NumericTolerance);
assert(result.GearMonitorError<spec.NumericTolerance);
end

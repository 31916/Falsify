function suite = fim_torque_inputs(spec)
%FIM_TORQUE_INPUTS Six declared ZOH waveforms; terminal value is held, not new.
if nargin == 0, spec = fim_torque_spec(); end
t = (0:spec.SampleTime:spec.StopTime)';
suite = struct('ID',{},'Name',{},'U',{});
for k=1:numel(spec.InputIDs)
    throttle = [spec.Throttle(k,:) spec.Throttle(k,end)]';
    suite(k) = struct('ID',spec.InputIDs{k},'Name',spec.InputNames{k}, ...
        'U',[t throttle zeros(size(t))]); %#ok<AGROW>
end
end

function spec = fim_torque_spec()
%FIM_TORQUE_SPEC Shared dynamics/monitor constants, not an experiment runner.
% This is a new research profile, NOT an ARCH benchmark specification.
spec.ID = 'FIM_AT_TORQUE_ACCEL_V1';
spec.StopTime = 30;
spec.SampleTime = 5;
spec.Solver = 'ode5';
spec.FixedStep = 0.01;
spec.InputRange = [60 100; 0 0]; % throttle %, brake=0
spec.FaultTime = 5;
spec.FaultLevel = 'Transmission/TorqueConverter';
spec.FaultSource = 'TorqueRatio';
spec.FaultDestination = 'Turbine';
spec.FaultDestinationPort = 2;
spec.FaultType = 'Bias/Offset';
spec.GearRange = [1 4];
spec.GearValues = [1 2 3 4];
spec.GearFormula = '[]_[0,30](gearlo /\ gearhi)';
spec.InputIDs = {'A','B','C','D','E','F'};
spec.InputNames = {'constant_60','constant_80','constant_100', ...
    'step_60_to_100','step_100_to_60','pulse_80_100_80'};
spec.Throttle = [60 60 60 60 60 60;80 80 80 80 80 80; ...
    100 100 100 100 100 100;60 60 60 100 100 100; ...
    100 100 100 60 60 60;80 80 100 100 80 80];
% The 95 mph target was selected in the retired normal-only pilot and is now
% frozen. Do not select a new threshold from formal fault results.
spec.AccelerationDeadline = 20;
spec.AccelerationFormulaTemplate = '<>_[0,20](fast)';
spec.NumericTolerance = 1e-8; % monitor agreement, NOT a relaxed gear range
spec.InjectionTolerance = 1e-10;
spec.ReplayTolerance = 1e-7;
spec.Scope = 'FIM research profile; finite baseline screens are not all-input safety proofs.';
end

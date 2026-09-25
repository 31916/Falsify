function spec = fim_torque_spec()
%FIM_TORQUE_SPEC Fixed, non-adaptive torque-ratio acceleration pilot.
% This is a new research profile, NOT an ARCH benchmark specification.
spec.ID = 'FIM_AT_TORQUE_ACCEL_V1';
spec.StopTime = 30;
spec.SampleTime = 5;
spec.Solver = 'ode5';
spec.FixedStep = 0.01;
spec.InputRange = [60 100; 0 0]; % pilot only: throttle %, brake=0
spec.FaultTime = 5;
spec.Deltas = [0.02 0.05 0.10]; % absolute subtraction, NOT percentages
spec.CaseIDs = {'B00','T01','T02','T03'};
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
% Declare selection BEFORE simulating faults. Use only the six normal runs:
% V = floor(min_i max_{0<=t<=20} speed_i(t) - 1 mph).
spec.AccelerationDeadline = 20;
spec.BaselineClearanceMPH = 1;
spec.TargetRoundingMPH = 1;
spec.AccelerationFormulaTemplate = '<>_[0,20](fast)';
spec.NumericTolerance = 1e-8; % monitor agreement, NOT a relaxed gear range
spec.InjectionTolerance = 1e-10;
spec.ReplayTolerance = 1e-7;
spec.Scope = ['Six deterministic calibration inputs; no falsification or learning; ' ...
    'no all-input safety claim and no tool-performance comparison.'];
end

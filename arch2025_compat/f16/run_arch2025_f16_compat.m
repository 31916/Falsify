function [tout, yout] = run_arch2025_f16_compat( ...
        officialDirectory, altg, Vtg, phig, thetag, psig, T)
%RUN_ARCH2025_F16_COMPAT Run the official F-16 model across AeroBench versions.
%
% The ARCH-COMP checkout contains an AeroBenchVV revision whose
% getDefaultSettings function emits legacy lower-case field names while
% RunF16Sim validates newer mixed-case names.  Keep the official checkout
% unchanged and add the missing aliases only for this invocation.

    officialDirectory = char(officialDirectory);
    aeroBenchDirectory = fullfile( ...
        officialDirectory, 'AeroBenchVV-develop');
    compatibilityDirectory = fileparts(mfilename('fullpath'));

    assert(isfolder(officialDirectory), ...
        'Official F16 directory was not found: %s', officialDirectory);
    assert(isfolder(aeroBenchDirectory), ...
        'AeroBenchVV-develop was not found: %s', aeroBenchDirectory);

    previousDirectory = pwd;
    directoryCleanup = onCleanup(@() cd(previousDirectory));

    cd(officialDirectory);
    addpath(genpath(aeroBenchDirectory), '-begin');
    addpath(officialDirectory, '-begin');
    addpath(compatibilityDirectory, '-begin');
    rehash path;

    powg = 9;
    alphag = deg2rad(2.1215);
    betag = 0;
    timeVector = 0:0.01:T;

    [flightLimits, ctrlLimits, autopilot] = getDefaultSettings();

    flightLimits = copyFieldIfMissing_( ...
        flightLimits, 'alphaMinDeg', 'alphaMin');
    flightLimits = copyFieldIfMissing_( ...
        flightLimits, 'alphaMaxDeg', 'alphaMax');
    flightLimits = copyFieldIfMissing_( ...
        flightLimits, 'betaMaxDeg', 'betaMax');
    flightLimits = copyFieldIfMissing_( ...
        flightLimits, 'psMaxAccelDeg', 'psMaxAccel');

    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'ThrottleMax', 'throttleMax');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'ThrottleMin', 'throttleMin');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'ElevatorMaxDeg', 'elevatorMax');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'ElevatorMinDeg', 'elevatorMin');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'AileronMaxDeg', 'aileronMax');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'AileronMinDeg', 'aileronMin');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'RudderMaxDeg', 'rudderMax');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'RudderMinDeg', 'rudderMin');
    ctrlLimits = copyFieldIfMissing_( ...
        ctrlLimits, 'MaxBankDeg', 'BankAngleMax');

    ctrlLimits.ThrottleMax = 0.7;
    autopilot.simpleGCAS = true;

    initialState = [ ...
        Vtg, alphag, betag, phig, thetag, psig, ...
        0, 0, 0, 0, 0, altg, powg ...
    ];

    orient = 4;
    [output, ~] = RunF16Sim( ...
        initialState, timeVector, orient, 'stevens', ...
        flightLimits, ctrlLimits, autopilot, ...
        false, false);

    tout = timeVector;
    yout = output(12, :);
end


function target = copyFieldIfMissing_(target, targetName, sourceName)

    if ~isfield(target, targetName) && isfield(target, sourceName)
        target.(targetName) = target.(sourceName);
    end
end

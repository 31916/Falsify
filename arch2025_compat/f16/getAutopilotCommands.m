function [u_ref, t_maneuver] = getAutopilotCommands( ...
        t, x_f16, xequil, ~, ~, ~, autopilot, resetTrue)
%GETAUTOPILOTCOMMANDS Compatibility copy of AeroBenchVV's GCAS commands.
%
% The ARCH-COMP checkout contains the published HTML source for this
% function but omits the corresponding .m file.  This implementation keeps
% the command modes exercised by run_f16: simple GCAS, basic speed control,
% and the steady-level hold enabled after recovery.

    if nargin < 8
        resetTrue = false;
    end

    persistent maneuverStart maneuverComplete rollComplete

    if isempty(maneuverStart) || t <= 0 || resetTrue
        maneuverStart = -1;
        maneuverComplete = -1;
        rollComplete = -1;
    end

    Nz = 0;
    ps = 0;
    Ny_r = 0;
    throttle = 0;

    if autopilot.simpleGCAS
        epsilonPhi = deg2rad(5);
        epsilonP = deg2rad(1);
        pathGoal = 0;
        desiredNz = 5;

        phi = x_f16(4);
        p = x_f16(7);
        theta = x_f16(5);
        alpha = x_f16(2);

        proportionalGain = 4;
        derivativeGain = proportionalGain * 0.3;
        maneuverStart = 2;

        if t < maneuverStart
            % Hold the trim commands until the GCAS maneuver starts.
        elseif rollComplete < 0
            radiansFromWingsLevel = round(phi / pi);

            if abs(phi - pi * radiansFromWingsLevel) < epsilonPhi && ...
                    abs(p) < epsilonP
                rollComplete = t;
            else
                ps = -(phi - pi * radiansFromWingsLevel) * ...
                    proportionalGain - p * derivativeGain;
            end
        elseif maneuverComplete < 0
            radiansFromNoseLevel = round((theta - alpha) / (2 * pi));

            if (theta - alpha) - 2 * pi * radiansFromNoseLevel > pathGoal
                maneuverComplete = t;
            else
                Nz = desiredNz;
            end
        else
            autopilot.steadyLevelFlightHold = true;
        end
    end

    if autopilot.basicSpeedControl
        throttle = -0.25 * (x_f16(1) - xequil(1));
    end

    if autopilot.steadyLevelFlightHold
        phi = x_f16(4);
        p = x_f16(7);
        theta = x_f16(5);
        alpha = x_f16(2);

        rollGain = 1;
        rollDerivativeGain = rollGain * 0.3;
        radiansFromWingsLevel = round(phi / pi);
        ps = -(phi - pi * radiansFromWingsLevel) * rollGain - ...
            p * rollDerivativeGain;

        pitchGain = 2;
        pitchDerivativeGain = rollGain * 0.3;
        radiansFromNoseLevel = round((theta - alpha) / pi);
        Nz = -(theta - alpha - pi * radiansFromNoseLevel) * ...
            pitchGain - p * pitchDerivativeGain;
    end

    t_maneuver = [maneuverStart, maneuverComplete, rollComplete];
    u_ref = [Nz; ps; Ny_r; throttle];
end

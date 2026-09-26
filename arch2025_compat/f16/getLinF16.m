function lin_f16 = getLinF16(xequil, uequil, printOn)
%GETLINF16 Toolbox-free compatibility adapter for AeroBenchVV.
%
% AeroBenchVV's nonlinear F-16 runner only reads the A/B/C/D matrices
% from the value returned by getLinF16.  The upstream implementation wraps
% those matrices in a Control System Toolbox `ss` object even when the
% selected plant is the nonlinear Stevens model.  This adapter preserves
% the matrices and metadata in a plain struct so the official nonlinear
% model can run when `ss` is unavailable.

    if nargin < 3
        printOn = false;
    end

    [A, B, C, D] = jacobFun(xequil, uequil, printOn);

    % Match the unit conversion performed by AeroBenchVV's implementation.
    angularOutputs = [2:4, 7:10];
    C(angularOutputs, :) = deg2rad(C(angularOutputs, :));
    D(angularOutputs, :) = deg2rad(D(angularOutputs, :));

    lin_f16 = struct();
    lin_f16.a = A;
    lin_f16.b = B;
    lin_f16.c = C;
    lin_f16.d = D;
    lin_f16.stateName = { ...
        'Vt', 'alpha', 'beta', 'phi', 'theta', 'psi', ...
        'p', 'q', 'r', 'pn', 'pe', 'alt', 'pow'};
    lin_f16.stateUnit = { ...
        'ft/s', 'rad', 'rad', 'rad', 'rad', 'rad', ...
        'rad', 'rad', 'rad', 'ft', 'ft', 'ft', 'lbs'};
    lin_f16.inputName = {'Throttle', 'Elevator', 'Aileron', 'Rudder'};
    lin_f16.inputUnit = {'percent', 'rad', 'rad', 'rad'};
    lin_f16.outputName = { ...
        'Az', 'q', 'alpha', 'theta', 'Vt', 'Ay', ...
        'p', 'r', 'beta', 'phi'};
    lin_f16.outputUnit = { ...
        'g''s', 'rad/s', 'rad', 'rad', 'ft/s', ...
        'g''s', 'rad/s', 'rad/s', 'rad', 'rad'};
    lin_f16.name = 'Linearized F-16 matrix data';

    if printOn
        disp(lin_f16);
    end
end

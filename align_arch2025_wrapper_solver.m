function align_arch2025_wrapper_solver(wrapperFile, officialModelFile)
%ALIGN_ARCH2025_WRAPPER_SOLVER Copy official solver settings to a wrapper.
%
% The wrapper and official replay must integrate the same physical model
% with the same numerical settings before trajectory differences can be
% interpreted as semantic differences.

    narginchk(2, 2);

    assert(isfile(wrapperFile), ...
        'Generated wrapper was not found:\n%s', wrapperFile);
    assert(isfile(officialModelFile), ...
        'Official model was not found:\n%s', officialModelFile);

    bdclose('all');
    officialHandle = load_system(officialModelFile);
    officialName = get_param(officialHandle, 'Name');
    loadedOfficialFile = get_param(officialHandle, 'FileName');
    assert(strcmp(loadedOfficialFile, officialModelFile), ...
        'Expected official model %s but loaded %s.', ...
        officialModelFile, loadedOfficialFile);

    wrapperHandle = load_system(wrapperFile);
    wrapperName = get_param(wrapperHandle, 'Name');
    loadedWrapperFile = get_param(wrapperHandle, 'FileName');
    assert(strcmp(loadedWrapperFile, wrapperFile), ...
        'Expected wrapper model %s but loaded %s.', ...
        wrapperFile, loadedWrapperFile);

    cleanupObject = onCleanup(@() bdclose('all'));

    settings = { ...
        'SolverType', ...
        'Solver', ...
        'FixedStep', ...
        'InitialStep', ...
        'MinStep', ...
        'MaxStep', ...
        'RelTol', ...
        'AbsTol' ...
    };

    for settingIndex = 1:numel(settings)
        settingName = settings{settingIndex};
        settingValue = get_param(officialName, settingName);
        set_param(wrapperName, settingName, settingValue);
    end

    save_system(wrapperName, wrapperFile);
end

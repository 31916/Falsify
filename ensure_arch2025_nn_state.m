function ensure_arch2025_nn_state(modelFile, expectedModelName)
%ENSURE_ARCH2025_NN_STATE Canonicalize the NN wrapper state as [Ref, Pos].
%
% Falsify assumes every state component is normalized from its declared
% output range to [-1, 1].  For the ARCH-COMP neural benchmark this means:
%
%   state(1) = Ref, normalized as Ref - 2       for Ref in [1, 3]
%   state(2) = Pos, normalized as 0.4*Pos - 1  for Pos in [0, 5]
%
% Older narmamaglev_RL wrappers used [Pos, Ref] and Pos/5.  This function
% repairs both the order and the normalization and is safe to call again.

    narginchk(1, 2);

    assert(isfile(modelFile), ...
        'NN wrapper was not found:\n%s', modelFile);

    originalPath = path;
    addpath(fileparts(modelFile), '-begin');
    pathCleanup = onCleanup(@() path(originalPath));

    bdclose('all');
    modelHandle = load_system(modelFile);
    modelName = get_param(modelHandle, 'Name');
    loadedModelFile = get_param(modelHandle, 'FileName');
    assert(strcmp(loadedModelFile, modelFile), ...
        'Expected NN wrapper %s but loaded %s.', ...
        modelFile, loadedModelFile);

    cleanupObject = onCleanup(@() close_system(modelName, 0));

    if nargin >= 2 && ~isempty(expectedModelName)
        assert(strcmp(modelName, expectedModelName), ...
            'Expected model %s but loaded %s.', ...
            expectedModelName, modelName);
    end

    normalizeRefBlock = [modelName, '/Normalize Ref'];
    normalizePosBlock = [modelName, '/Normalize Pos'];
    normalizePosBiasBlock = [modelName, '/Normalize Pos Bias'];
    stateMuxBlock = [modelName, '/State Mux'];

    assert(getSimulinkBlockHandle(normalizeRefBlock) ~= -1, ...
        'Normalize Ref block is missing from %s.', modelName);
    assert(getSimulinkBlockHandle(normalizePosBlock) ~= -1, ...
        'Normalize Pos block is missing from %s.', modelName);
    assert(getSimulinkBlockHandle(stateMuxBlock) ~= -1, ...
        'State Mux block is missing from %s.', modelName);

    set_param(normalizeRefBlock, 'Bias', '-2');
    set_param(normalizePosBlock, 'Gain', '0.4');
    set_param(stateMuxBlock, 'Inputs', '2');

    if getSimulinkBlockHandle(normalizePosBiasBlock) == -1
        posPosition = get_param(normalizePosBlock, 'Position');
        add_block( ...
            'simulink/Math Operations/Bias', ...
            normalizePosBiasBlock, ...
            'Bias', '-1', ...
            'Position', posPosition + [125 0 125 0] ...
        );
    else
        set_param(normalizePosBiasBlock, 'Bias', '-1');
    end

    refPorts = get_param(normalizeRefBlock, 'PortHandles');
    posGainPorts = get_param(normalizePosBlock, 'PortHandles');
    posBiasPorts = get_param(normalizePosBiasBlock, 'PortHandles');
    muxPorts = get_param(stateMuxBlock, 'PortHandles');

    disconnectInput_(muxPorts.Inport(1));
    disconnectInput_(muxPorts.Inport(2));
    disconnectInput_(posBiasPorts.Inport(1));

    add_line(modelName, ...
        posGainPorts.Outport(1), posBiasPorts.Inport(1), ...
        'autorouting', 'on');
    add_line(modelName, ...
        refPorts.Outport(1), muxPorts.Inport(1), ...
        'autorouting', 'on');
    add_line(modelName, ...
        posBiasPorts.Outport(1), muxPorts.Inport(2), ...
        'autorouting', 'on');

    assert(strcmp(sourceBlockName_(muxPorts.Inport(1)), 'Normalize Ref'), ...
        'State Mux input 1 must be normalized Ref.');
    assert(strcmp(sourceBlockName_(muxPorts.Inport(2)), ...
        'Normalize Pos Bias'), ...
        'State Mux input 2 must be normalized Pos.');

    save_system(modelName, modelFile);
end


function disconnectInput_(inputPort)

    lineHandle = get_param(inputPort, 'Line');
    if lineHandle ~= -1
        delete_line(lineHandle);
    end
end


function blockName = sourceBlockName_(inputPort)

    lineHandle = get_param(inputPort, 'Line');
    assert(lineHandle ~= -1, 'Expected input port is not connected.');
    sourcePort = get_param(lineHandle, 'SrcPortHandle');
    sourceBlock = get_param(sourcePort, 'Parent');
    blockName = get_param(sourceBlock, 'Name');
end

function [firstOutput, secondOutput] = arch2025_sb_predict_step( ...
        networkFile, inputValue, queryTime, sequenceLength, outputDimension)
%ARCH2025_SB_PREDICT_STEP Advance a FalBenchGen LSTM exactly once per tick.

    persistent network cachedNetworkFile lastTime lastOutput

    networkFile = char(networkFile);
    queryTime = double(queryTime);
    sequenceLength = double(sequenceLength);
    outputDimension = double(outputDimension);

    newEpisode = isempty(lastTime) || queryTime < lastTime - 1.0e-9;
    changedNetwork = isempty(cachedNetworkFile) || ...
        ~strcmp(cachedNetworkFile, networkFile);

    if isempty(network) || newEpisode || changedNetwork
        assert(isfile(networkFile), ...
            'FalBenchGen network was not found: %s', networkFile);
        loaded = load(networkFile, 'net');
        assert(isfield(loaded, 'net'), ...
            'FalBenchGen MAT file does not contain net: %s', networkFile);
        network = resetState(loaded.net);
        cachedNetworkFile = networkFile;
        lastTime = -inf;
        lastOutput = zeros(outputDimension, 1);
    end

    if abs(queryTime - lastTime) <= 1.0e-9
        [firstOutput, secondOutput] = components_( ...
            lastOutput, outputDimension);
        return;
    end

    % FalBenchGen trains on 24 samples (four six-sample control points).
    % The t=24 Simulink endpoint holds the 24th prediction instead of
    % advancing the recurrent network to an unintended 25th sample.
    if queryTime >= sequenceLength
        [firstOutput, secondOutput] = components_( ...
            lastOutput, outputDimension);
        lastTime = queryTime;
        return;
    end

    [network, prediction] = predictAndUpdateState( ...
        network, double(inputValue), 'MiniBatchSize', 1);
    prediction = double(prediction(:));
    assert(numel(prediction) == outputDimension, ...
        'FalBenchGen output dimension mismatch.');
    lastOutput = prediction;
    lastTime = queryTime;
    [firstOutput, secondOutput] = components_( ...
        lastOutput, outputDimension);
end


function [firstOutput, secondOutput] = components_(output, outputDimension)
    firstOutput = double(output(1));
    secondOutput = 0.0;
    if outputDimension > 1
        secondOutput = double(output(2));
    end
end

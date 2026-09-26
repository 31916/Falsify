function dataFile = prepare_arch2025_at_data(destinationDirectory)
%PREPARE_ARCH2025_AT_DATA Obtain the support data used by the official AT model.
%
% The ARCH-COMP 2025 checkout contains Autotrans_shift.mdl, but that model
% loads sldemo_autotrans_data.mat from the MathWorks automatic-transmission
% example.  The support file is therefore obtained through MATLAB's example
% mechanism and kept outside Git.

    repoDirectory = fileparts(mfilename('fullpath'));
    if nargin < 1 || strlength(string(destinationDirectory)) == 0
        destinationDirectory = fullfile( ...
            repoDirectory, '.deps', 'arch2025', 'mathworks');
    end

    destinationDirectory = char(destinationDirectory);
    fileName = 'sldemo_autotrans_data.mat';
    dataFile = locateExistingFile_(fileName, destinationDirectory);

    if isempty(dataFile)
        if ~isfolder(destinationDirectory)
            mkdir(destinationDirectory);
        end

        try
            openExample(fileName, 'workDir', destinationDirectory);
        catch exception
            error( ...
                'Falsify:Arch2025AtDataDownloadFailed', ...
                [ ...
                    'MATLAB could not obtain %s from the installed ' ...
                    'MathWorks examples. Ensure that Simulink and ' ...
                    'Stateflow examples are available, then retry.\n%s' ...
                ], ...
                fileName, exception.message);
        end

        matches = dir(fullfile(destinationDirectory, '**', fileName));
        if ~isempty(matches)
            dataFile = fullfile(matches(1).folder, matches(1).name);
        end
    end

    assert(isfile(dataFile), ...
        'Falsify:Arch2025AtDataMissing', ...
        'The MathWorks example did not provide %s.', fileName);

    validateDataFile_(dataFile);
    setenv('FALSIFY_ARCH2025_AT_DATA', dataFile);

    fprintf('ARCH-COMP 2025 AT data: %s\n', dataFile);
    fprintf('FALSIFY_ARCH2025_AT_DATA was set for this MATLAB session.\n');
end


function dataFile = locateExistingFile_(fileName, destinationDirectory)

    dataFile = '';
    candidates = {
        getenv('FALSIFY_ARCH2025_AT_DATA')
        which(fileName)
        fullfile(destinationDirectory, fileName)
        fullfile(matlabroot, 'toolbox', 'simulink', ...
            'simdemos', 'automotive', fileName)
        fullfile(matlabroot, 'examples', 'simulink', 'data', fileName)
    };

    for candidateIndex = 1:numel(candidates)
        candidate = char(string(candidates{candidateIndex}));
        if isempty(candidate)
            continue;
        end
        if isfolder(candidate)
            candidate = fullfile(candidate, fileName);
        end
        if isfile(candidate)
            dataFile = candidate;
            return;
        end
    end

    if isfolder(destinationDirectory)
        matches = dir(fullfile(destinationDirectory, '**', fileName));
        if ~isempty(matches)
            dataFile = fullfile(matches(1).folder, matches(1).name);
        end
    end
end


function validateDataFile_(dataFile)

    requiredVariables = {
        'converter_data'
        'vehicledata'
        'thvec'
        'nevec'
        'emap'
        'upth'
        'uptab'
        'downth'
        'downtab'
        'TWAIT'
    };
    variableInfo = whos('-file', dataFile);
    fileVariables = string({variableInfo.name});
    missingVariables = setdiff(string(requiredVariables), fileVariables);

    assert(isempty(missingVariables), ...
        'Falsify:InvalidArch2025AtData', ...
        'AT support data is missing variable(s): %s', ...
        strjoin(cellstr(missingVariables), ', '));
end

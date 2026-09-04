clearvars;
clc;

% Publish a complete ARCH-COMP 2025 validation run, or assemble the older
% focused runs when no explicit source is supplied. Later sources take
% priority when a case was run more than once.

repoDirectory = fileparts(mfilename('fullpath'));
resultsRoot = fullfile(repoDirectory, 'results', 'arch2025');

explicitSource = strtrim(string( ...
    getenv('FALSIFY_ARCH2025_FINAL_SOURCE') ...
));

if strlength(explicitSource) > 0
    if ~isfile(explicitSource)
        explicitSource = fullfile(repoDirectory, explicitSource);
    end
    sourceFiles = explicitSource;
else
    sourceFiles = string(fullfile(resultsRoot, {
        'all/arch2025_all_summary.csv'
        'selected/at__/arch2025_all_summary.csv'
        'selected/afc__/arch2025_all_summary.csv'
        'selected/cc___i2__/arch2025_all_summary.csv'
        'selected/nn___i2__/arch2025_all_summary.csv'
        'selected/__acer/arch2025_all_summary.csv'
        'selected/sb__/arch2025_all_summary.csv'
        'selected/sc__/arch2025_all_summary.csv'
        'selected/f16__/arch2025_all_summary.csv'
    }));
end

for sourceIndex = 1:numel(sourceFiles)
    assert(isfile(sourceFiles(sourceIndex)), ...
        'Required focused result is missing: %s', sourceFiles(sourceIndex));
end

caseResults = containers.Map('KeyType', 'char', 'ValueType', 'any');
template = emptyResult_();
resultFields = fieldnames(template);

for sourceIndex = 1:numel(sourceFiles)
    sourceTable = readtable(sourceFiles(sourceIndex), 'TextType', 'string');
    assert(all(ismember({'CaseID', 'OverallPass'}, ...
        sourceTable.Properties.VariableNames)), ...
        'Result table has no CaseID/OverallPass columns: %s', ...
        sourceFiles(sourceIndex));

    for row = 1:height(sourceTable)
        if ~logicalValue_(sourceTable.OverallPass(row))
            continue;
        end

        result = template;
        for fieldIndex = 1:numel(resultFields)
            fieldName = resultFields{fieldIndex};
            if ismember(fieldName, sourceTable.Properties.VariableNames)
                result.(fieldName) = normalizedValue_( ...
                    fieldName, sourceTable.(fieldName)(row, :));
            end
        end

        result.Status = "VALIDATED";
        result.OverallPass = true;
        result.FalsifyClassification = robustnessClassText_( ...
            result.FalsifyRobustness, 1.0e-9);
        result.OfficialClassification = robustnessClassText_( ...
            result.OfficialRobustness, 1.0e-9);
        result.InputTraceFile = relativeRepositoryPath_( ...
            result.InputTraceFile, repoDirectory);
        result.StateTraceFile = relativeRepositoryPath_( ...
            result.StateTraceFile, repoDirectory);

        caseResults(char(result.CaseID)) = result;
    end
end

assert(caseResults.Count == 196, ...
    'Expected 196 unique validated cases, but assembled %d.', ...
    caseResults.Count);

resultCells = values(caseResults);
results = vertcat(resultCells{:});
summaryTable = struct2table(results);

modelOrder = categorical(summaryTable.Model, ...
    ["SB", "AT", "AFC", "CC", "NN", "F16", "SC"], ...
    'Ordinal', true);
algorithmOrder = categorical(summaryTable.Algorithm, ...
    ["RAND", "A3C", "ACER", "DDQN"], 'Ordinal', true);
summaryTable.ModelOrder = modelOrder;
summaryTable.AlgorithmOrder = algorithmOrder;
summaryTable = sortrows(summaryTable, ...
    {'ModelOrder', 'Requirement', 'Instance', 'AlgorithmOrder'});
summaryTable.ModelOrder = [];
summaryTable.AlgorithmOrder = [];

expectedModelCounts = [20, 80, 12, 48, 24, 4, 8];
modelNames = ["SB", "AT", "AFC", "CC", "NN", "F16", "SC"];
for modelIndex = 1:numel(modelNames)
    actualCount = sum(summaryTable.Model == modelNames(modelIndex));
    assert(actualCount == expectedModelCounts(modelIndex), ...
        'Unexpected %s case count: %d.', modelNames(modelIndex), actualCount);
end
for algorithm = ["RAND", "A3C", "ACER", "DDQN"]
    assert(sum(summaryTable.Algorithm == algorithm) == 49, ...
        'Unexpected %s case count.', algorithm);
end

finalDirectory = fullfile(resultsRoot, 'final');
if ~isfolder(finalDirectory)
    mkdir(finalDirectory);
end

summaryFile = fullfile(finalDirectory, 'arch2025_all_summary.csv');
writetable(summaryTable, summaryFile);

statusTable = summaryTable(:, {
    'Model', 'Requirement', 'Instance', 'Algorithm', ...
    'FalsifyRunPass', 'InputPass', 'OfficialReplayPass', ...
    'FalsifyClassification', 'OfficialClassification', ...
    'ClassificationAgreementPass', 'OverallPass', 'Status'});
statusTable.Properties.VariableNames{6} = 'InputValidationPass';
writetable(statusTable, ...
    fullfile(finalDirectory, 'arch2025_status.csv'));

violationTable = summaryTable( ...
    summaryTable.OfficialClassification == "VIOLATED", {
    'CaseID', 'Model', 'Requirement', 'Instance', 'Algorithm', 'Seed', ...
    'FalsifyRobustness', 'FalsifyClassification', ...
    'OfficialRobustness', 'OfficialClassification', ...
    'InputPass', 'OfficialReplayPass', ...
    'ClassificationAgreementPass', 'InputTraceFile'});
writetable(violationTable, ...
    fullfile(finalDirectory, 'arch2025_official_violations.csv'));

reportFile = fullfile(finalDirectory, 'arch2025_final_report.txt');
report = fopen(reportFile, 'w');
assert(report ~= -1, 'Could not create final report: %s', reportFile);
cleanup = onCleanup(@() fclose(report));

fprintf(report, 'ARCH-COMP 2025 Falsify final validation result\n');
fprintf(report, '===============================================\n\n');
fprintf(report, 'Scope: SB, AT, AFC, CC, NN, F16, SC\n');
fprintf(report, 'Algorithms: RAND, A3C, ACER, DDQN\n');
fprintf(report, 'Budget: one Falsify episode per case\n');
fprintf(report, 'PM: excluded because the official local model is unavailable\n\n');
fprintf(report, 'Source summary file(s):\n');
for sourceIndex = 1:numel(sourceFiles)
    fprintf(report, '  %s\n', sourceFiles(sourceIndex));
end
fprintf(report, '\n');
fprintf(report, 'Validated: %d / %d\n', ...
    sum(summaryTable.OverallPass), height(summaryTable));
fprintf(report, 'Official replay: %d / %d\n', ...
    sum(summaryTable.OfficialReplayPass), height(summaryTable));
fprintf(report, 'Classification agreement: %d / %d\n', ...
    sum(summaryTable.ClassificationAgreementPass), height(summaryTable));
fprintf(report, 'Official violations found: %d\n', ...
    sum(summaryTable.OfficialClassification == "VIOLATED"));
fprintf(report, 'Trajectory diagnostics within tolerance: %d / %d\n\n', ...
    sum(summaryTable.TrajectoryEquivalencePass), height(summaryTable));

for modelIndex = 1:numel(modelNames)
    rows = summaryTable.Model == modelNames(modelIndex);
    fprintf(report, '%s: %d / %d validated\n', ...
        modelNames(modelIndex), sum(summaryTable.OverallPass(rows)), sum(rows));
end

fprintf('\nFinal summary: %s\n', summaryFile);
fprintf('Status table:  %s\n', ...
    fullfile(finalDirectory, 'arch2025_status.csv'));
fprintf('Violations:    %s\n', ...
    fullfile(finalDirectory, 'arch2025_official_violations.csv'));
fprintf('Report:        %s\n', reportFile);


function value = normalizedValue_(fieldName, value)

    stringFields = {
        'CaseID', 'Model', 'Requirement', 'Algorithm', 'Status', ...
        'FalsifyClassification', 'OfficialClassification', ...
        'InputMessage', 'InputTraceFile', 'StateTraceFile', ...
        'ErrorIdentifier', 'ErrorMessage'};
    logicalFields = {
        'InputRangePass', 'InputStructurePass', 'InputPass', ...
        'FalsifyRunPass', 'OfficialReplayPass', ...
        'ClassificationAgreementPass', 'TrajectoryEquivalencePass', ...
        'OverallPass'};

    if ismember(fieldName, stringFields)
        value = string(value(1));
    elseif ismember(fieldName, logicalFields)
        value = logicalValue_(value(1));
    elseif iscell(value)
        value = value{1};
    else
        value = double(value(1));
    end
end


function value = logicalValue_(input)

    if iscell(input)
        input = input{1};
    end
    if islogical(input)
        value = input(1);
    elseif isnumeric(input)
        value = input(1) ~= 0;
    else
        value = any(strcmpi(strtrim(string(input(1))), ...
            ["1", "true", "yes", "pass"]));
    end
end


function value = robustnessClassText_(robustness, tolerance)

    if robustness < -tolerance
        value = "VIOLATED";
    elseif robustness > tolerance
        value = "SATISFIED";
    else
        value = "BOUNDARY";
    end
end


function value = relativeRepositoryPath_(value, repoDirectory)

    value = string(value);
    prefix = string(repoDirectory) + filesep;
    if startsWith(value, prefix)
        value = extractAfter(value, strlength(prefix));
    end
end


function result = emptyResult_()

    result = struct( ...
        'CaseID', "", ...
        'Model', "", ...
        'Requirement', "", ...
        'Instance', NaN, ...
        'Algorithm', "", ...
        'Seed', NaN, ...
        'Status', "NOT_RUN", ...
        'Episodes', NaN, ...
        'ElapsedSeconds', NaN, ...
        'FalsifyRobustness', NaN, ...
        'FalsifyClassification', "", ...
        'OfficialRobustness', NaN, ...
        'OfficialClassification', "", ...
        'InputRangePass', false, ...
        'InputStructurePass', false, ...
        'InputPass', false, ...
        'InputMessage', "", ...
        'FalsifyRunPass', false, ...
        'OfficialReplayPass', false, ...
        'ClassificationAgreementPass', false, ...
        'MaximumTrajectoryError', NaN, ...
        'TrajectoryEquivalencePass', false, ...
        'OverallPass', false, ...
        'InputTraceFile', "", ...
        'StateTraceFile', "", ...
        'ErrorIdentifier', "", ...
        'ErrorMessage', "");
end

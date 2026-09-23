function runDirectory = test_fim_migration(previousRun,runDirectory)
%TEST_FIM_MIGRATION Regenerate models and compare independent saved waveforms.
% Writes a NEW run only. Does not modify the previous run or launch a search.
test_fim_at_spec();
if nargin<2, runDirectory=run_fim_at_experiments('prepare'); end
assert(~strcmp(previousRun,runDirectory),'Never write validation into the historical run.');
folder=fullfile(runDirectory,'migration_validation');
if ~isfolder(folder), mkdir(folder); end
ids={'B00','F01','F02','F07','F09','F10'};
rows=struct([]);
for k=1:numel(ids)
    id=ids{k};
    original=load(fullfile(previousRun,'exp1',[id '_U02.mat']));
    file=fullfile(folder,[id '_U02.mat']);
    if ~isfile(file), fim_at_external(runDirectory,id,original.trace.U,file); end
    generated=load(file);
    err=max(abs(generated.trace.Y-original.trace.Y),[],'all');
    assert(isequal(generated.trace.T,original.trace.T));
    assert(err<1e-7 && abs(generated.trace.Rho-original.trace.Rho)<1e-9);
    assert(generated.normal.Rho>0 && generated.trace.InjectionError<1e-7);
    assert(isequal(generated.u,original.trace.U));
    row=struct('Case',id,'Input','U02','MaxWaveformError',err, ...
        'Robustness',generated.trace.Rho);
    if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
end
validation=struct2table(rows);
writetable(validation,fullfile(folder,'validation.csv'));
disp(validation);
fprintf('PASS: relocation regression, 11 generated models and 6 saved-waveform comparisons.\n');
fprintf('MIGRATION_RUN=%s\n',runDirectory);
end

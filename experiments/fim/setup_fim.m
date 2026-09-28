function paths = setup_fim()
%SETUP_FIM Add only this experiment's entry points; no simulations or downloads.
root=fileparts(mfilename('fullpath'));
addpath(root,fullfile(root,'config'),fullfile(root,'matlab'),fullfile(root,'tests'));
paths=fim_paths();
addpath(paths.Repo,fullfile(paths.Repo,'arch2025_generated'),paths.ModelData);
threads=str2double(getenv('FIM_CPU_THREADS'));
if ~isnan(threads)
    assert(ismember(threads,[1 4]));
    maxNumCompThreads(threads);
    assert(maxNumCompThreads==threads,'Numerical thread limit was not applied.');
end
runtime=getenv('FIM_WORK_DIR');
if ~isempty(runtime)
    assert(isfolder(runtime),'Worker directory must be created before MATLAB starts.');
    Simulink.fileGenControl('set','CacheFolder',fullfile(runtime,'cache'), ...
        'CodeGenFolder',fullfile(runtime,'codegen'),'createDir',true);
    cd(runtime);
end
fprintf('FIM experiment: %s\n',root);
end

function setup_fim_linux
% Compile platform-specific monitors only in this dedicated checkout.
paths=fim_paths(); root=paths.Repo;
assert(isunix && ~ismac,'This setup is for the dedicated Linux checkout.');
assert(license('test','Simulink')==1,'Simulink license unavailable.');
original=pwd; cleanup=onCleanup(@() cd(original)); %#ok<NASGU>
folder=fullfile(root,'s-taliro','dp_taliro'); cd(folder);
mex('-compatibleArrayDims','-outdir',folder,'mx_dp_taliro.c','cache.c','distances.c', ...
    'lex.c','DynamicProgramming.c','parse.c','rewrt.c');
folder=fullfile(root,'s-taliro','monitor'); cd(folder);
mex('-outdir',folder,'on_line.c');
pyenv('Version',fullfile(root,'.venv-falsify','bin','python'));
disp(py.sys.version); disp(version); disp(ver('Simulink'));
fprintf('PASS: Linux MEX monitors compiled and Python loaded.\n');
end

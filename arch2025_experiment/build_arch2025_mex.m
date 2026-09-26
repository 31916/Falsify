function outputFiles = build_arch2025_mex(outputDirectory)
%BUILD_ARCH2025_MEX Build required S-TaLiRo MEX files outside the checkout.

    scriptDirectory = fileparts(mfilename('fullpath'));
    repoDirectory = fileparts(scriptDirectory);
    dpSourceDirectory = fullfile(repoDirectory, 's-taliro', 'dp_taliro');
    monitorSourceDirectory = fullfile(repoDirectory, 's-taliro', 'monitor');

    if nargin < 1 || strlength(string(outputDirectory)) == 0
        outputDirectory = fullfile(repoDirectory, 'build', 'mex');
    end
    outputDirectory = char(outputDirectory);

    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end

    sourceFiles = {
        'mx_dp_taliro.c'
        'cache.c'
        'distances.c'
        'lex.c'
        'DynamicProgramming.c'
        'parse.c'
        'rewrt.c'
    };
    sourceFiles = cellfun( ...
        @(name) fullfile(dpSourceDirectory, name), ...
        sourceFiles, ...
        'UniformOutput', false);

    mex( ...
        '-compatibleArrayDims', ...
        '-outdir', outputDirectory, ...
        sourceFiles{:});

    dpOutputFile = fullfile( ...
        outputDirectory, ['mx_dp_taliro.', mexext]);
    assert(isfile(dpOutputFile), ...
        'Falsify:Arch2025MexBuildFailed', ...
        'dp_taliro MEX was not created: %s', dpOutputFile);

    mex( ...
        '-outdir', outputDirectory, ...
        fullfile(monitorSourceDirectory, 'on_line.c'));

    monitorOutputFile = fullfile( ...
        outputDirectory, ['on_line.', mexext]);
    assert(isfile(monitorOutputFile), ...
        'Falsify:Arch2025MexBuildFailed', ...
        'Online monitor MEX was not created: %s', monitorOutputFile);

    outputFiles = string({dpOutputFile, monitorOutputFile});
    fprintf('ARCH-COMP 2025 dp_taliro MEX: %s\n', dpOutputFile);
    fprintf('ARCH-COMP 2025 online monitor MEX: %s\n', ...
        monitorOutputFile);
end

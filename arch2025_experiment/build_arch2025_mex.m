function outputFile = build_arch2025_mex(outputDirectory)
%BUILD_ARCH2025_MEX Build dp_taliro outside the source checkout.

    scriptDirectory = fileparts(mfilename('fullpath'));
    repoDirectory = fileparts(scriptDirectory);
    sourceDirectory = fullfile(repoDirectory, 's-taliro', 'dp_taliro');

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
        @(name) fullfile(sourceDirectory, name), ...
        sourceFiles, ...
        'UniformOutput', false);

    mex( ...
        '-compatibleArrayDims', ...
        '-outdir', outputDirectory, ...
        sourceFiles{:});

    outputFile = fullfile( ...
        outputDirectory, ['mx_dp_taliro.', mexext]);
    assert(isfile(outputFile), ...
        'Falsify:Arch2025MexBuildFailed', ...
        'dp_taliro MEX was not created: %s', outputFile);
    fprintf('ARCH-COMP 2025 dp_taliro MEX: %s\n', outputFile);
end

function paths = setup_fim()
%SETUP_FIM Add only this experiment's entry points; no simulations or downloads.
root=fileparts(mfilename('fullpath'));
addpath(root,fullfile(root,'config'),fullfile(root,'matlab'),fullfile(root,'tests'));
paths=fim_paths();
addpath(paths.Repo,fullfile(paths.Repo,'arch2025_generated'),paths.ModelData);
fprintf('FIM experiment: %s\n',root);
end

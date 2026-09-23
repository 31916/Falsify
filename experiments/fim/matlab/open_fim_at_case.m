function open_fim_at_case(runDirectory, caseID)
%OPEN_FIM_AT_CASE Open a generated plant with its FIM dependency available.
% Example: open_fim_at_case(runDirectory,'F02'). Does not run or save it.
paths=fim_paths();
runDirectory=char(java.io.File(runDirectory).getCanonicalPath());
data=load(fullfile(runDirectory,'cases.mat'),'cases');
index=find(strcmp({data.cases.ID},caseID));
assert(isscalar(index),'Choose B00 (baseline) or F01 through F10.');
c=data.cases(index);
library=fullfile(runDirectory,'FInjLib.slx');
if bdIsLoaded('FInjLib')
    assert(strcmp(get_param('FInjLib','FileName'),library), ...
        'Another FInjLib is open. Close it manually before opening this run.');
end
addpath(paths.ModelData);
load_system(library); set_param('FInjLib','Lock','off');
file=fullfile(runDirectory,'models',[c.Model '.slx']);
if ~isfile(file), file=fullfile(runDirectory,'models',[c.Model '.mdl']); end
if bdIsLoaded(c.Model)
    assert(strcmp(get_param(c.Model,'FileName'),file), ...
        'A model with the same name from another run is open. Close it manually.');
end
open_system(file);
if ~isempty(c.FaultBlock)
    hilite_system([c.Model '/' c.FaultBlock],'find');
end
end

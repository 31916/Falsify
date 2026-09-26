function prepare_fim_stuck(campaign)
paths=fim_paths(); protocol=jsondecode(fileread(fullfile(campaign,'protocol.json')));
oldDir=pwd; oldPath=path; oldWarning=warning;
cleanup=onCleanup(@()restore_(oldDir,oldPath,oldWarning)); %#ok<NASGU>
addpath(paths.ModelData);
plants=fullfile(campaign,'plants');
copyfile(paths.ATModel,fullfile(plants,'fim_stuck_B00.mdl'));
load_system(fullfile(plants,'fim_stuck_B00.mdl')); configure_('fim_stuck_B00','');
save_system('fim_stuck_B00'); close_system('fim_stuck_B00',0);
cases=struct('ID','B00','Model','fim_stuck_B00','FaultBlock','','Onset',0,'Duration',0);
index=0;
for onset=reshape(protocol.onsets_seconds,1,[])
 for duration=reshape(protocol.durations_seconds,1,[])
    index=index+1; id=sprintf('S%02d',index); name=['fim_stuck_' id];
    staging=fullfile(campaign,['generation_' id]); mkdir(staging);
    for folder={'Configuration','FaultInjector_Master','models'}, mkdir(fullfile(staging,folder{1})); end
    for file={'FISingle.m','FCSingle.m','Init_sys_input.m','fault_suite.m','replace_suite.m','fim_arrange_system.m'}
        copyfile(fullfile(paths.FIMPatched,file{1}),staging);
    end
    for patch={'fim-masked-subsystems.patch','fim-stuck-duration.patch'}
        [status,output]=system(sprintf('patch --batch --forward -p1 -d "%s" < "%s"', ...
            staging,fullfile(paths.Experiment,'dependencies',patch{1})));
        assert(status==0,'FIM patch failed: %s',output);
    end
    copyfile(fullfile(paths.FIMOriginal,'LICENSE'),staging);
    library=fullfile(staging,'FaultInjector_Master','FInjLib.slx');
    copyfile(fullfile(paths.FIMOriginal,'FaultInjector_Master','FInjLib.slx'),library);
    load_system(library); set_param('FInjLib','Lock','off');
    % Keep native memory/switch wiring. Replace only its defective initializer.
    mask=Simulink.Mask.get('FInjLib/Stuck-at');
    set_param('FInjLib/Stuck-at','FaultOccurenceTime',num2str(onset));
    mask.Initialization='fim_configure_stuck(gcb);';
    save_system('FInjLib'); close_system('FInjLib',0);
    copyfile(fullfile(paths.FIMOriginal,'Configuration','FIToolInitialization.mat'),fullfile(staging,'Configuration'));
    copyfile(paths.ATModel,fullfile(staging,'models',[name '.mdl']));
    constants=struct(); save(fullfile(staging,'Configuration','AT_constants.mat'),'-struct','constants');
    config=table({['models/' name '.mdl']},{'AT_constants.mat'},{'.'},{'faults.csv'}, ...
        'VariableNames',{'model','constants_thresholds','fault_injector_folder','fault_list'});
    faults=table(string(protocol.fault_level),string(protocol.fault_source),"NA","NA","Stuck-at", ...
        'VariableNames',{'level_final','Src_or_InportName','Dst_or_OutportName','ParentBlock','Faulttype_ft'});
    enabled=table(1,"NA",onset,"Constant time",duration,"NA", ...
        'VariableNames',{'FaultBlock_Num','Faultvalue_fv','FaultOccurenceTime_fot','FaultEffect_fe','Fault Duration_fd','Fault Operator Number_fo'});
    writetable(config,fullfile(staging,'Configuration','config.csv'));
    writetable(faults,fullfile(staging,'Configuration','faults.csv'));
    writetable(enabled,fullfile(staging,'Configuration','enable.csv'));
    cd(staging); addpath(staging);
    clear FISingle FCSingle Init_sys_input fault_suite replace_suite fim_arrange_system
    FISingle('config.csv','fault_table');
    ft=readtable(fullfile(staging,'fault_table','Fault_table.xls')); assert(height(ft)==1);
    FCSingle('config.csv','fault_table','enable.csv');
    mutant=[name '_copy']; block=[char(ft{1,3}) '/' char(ft{1,2})];
    relative=char(extractAfter(string(block),strlength(mutant)+1));
    ph=get_param(block,'PortHandles');
    src=get_param(get_param(ph.Inport,'Line'),'SrcPortHandle');
    dst=get_param(get_param(ph.Outport,'Line'),'DstPortHandle');
    assert(strcmp(get_param(src,'Parent'),[mutant '/' protocol.fault_level '/gear']));
    assert(isscalar(dst) && strcmp(get_param(get_param(dst,'Parent'),'BlockType'),'Lookup'));
    fim_configure_stuck(block); configure_(mutant,relative);
    save_system(mutant,fullfile(plants,[name '.slx'])); close_system(name,0);
    if index==1, save_system('FInjLib',fullfile(campaign,'FInjLib.slx')); end
    close_system('FInjLib',0); cd(oldDir); path(oldPath); warning(oldWarning); addpath(paths.ModelData);
    cases(end+1)=struct('ID',id,'Model',name,'FaultBlock',relative,'Onset',onset,'Duration',duration); %#ok<AGROW>
    fprintf('STUCK PREPARED %s: [%g,%g) seconds\n',id,onset,onset+duration);
 end
end
writetable(struct2table(cases),fullfile(campaign,'fault_catalog.csv'));
end

function configure_(model,relative)
assert(strcmp(get_param(model,'Solver'),'ode5') && str2double(get_param(model,'FixedStep'))==.01);
set_param(model,'SimulationMode','normal','StopTime','30');
ports=find_system(model,'SearchDepth',1,'BlockType','Inport');
for k=1:numel(ports), set_param(ports{k},'Interpolate','off','SampleTime','5'); end
ports=find_system(model,'FindAll','on','LookUnderMasks','all','Type','port','PortType','outport');
for k=1:numel(ports), set_param(ports(k),'DataLogging','off'); end
log_([model '/Transmission/TransmissionRatio/gear'],'gear_command');
if ~isempty(relative)
    log_([model '/' relative],'gear_applied');
    log_([model '/' relative '/Switch'],'fault_gate');
end
lookup=find_system([model '/Transmission/TransmissionRatio'],'SearchDepth',1,'LookUnderMasks','all','BlockType','Lookup');
assert(numel(lookup)==1); log_(lookup{1},'gear_ratio');
end

function log_(block,name)
p=get_param(block,'PortHandles');
set_param(p.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name);
end

function restore_(directory,oldPath,oldWarning)
cd(directory); path(oldPath); warning(oldWarning);
end

function prepare_fim_torque_models(campaign)
% Generate new FIM mutants with native FISingle/FCSingle, never edit old runs.
paths=fim_paths(); spec=fim_torque_spec();
protocol=jsondecode(fileread(fullfile(campaign,'protocol.json')));
addpath(paths.ModelData); oldDir=pwd; oldPath=path; oldWarning=warning;
cleanup=onCleanup(@()restore_(oldDir,oldPath,oldWarning)); %#ok<NASGU>
assert(~bdIsLoaded('FInjLib'),'Use a fresh MATLAB process.');
plants=fullfile(campaign,'plants');
copyfile(paths.ATModel,fullfile(plants,'fim_tq_B00.mdl'));
load_system(fullfile(plants,'fim_tq_B00.mdl'));
set_param('fim_tq_B00','SimulationMode','normal','StopTime','30');
ports=find_system('fim_tq_B00','SearchDepth',1,'BlockType','Inport');
for k=1:numel(ports), set_param(ports{k},'Interpolate','off','SampleTime','5'); end
outports=find_system('fim_tq_B00','FindAll','on','LookUnderMasks','all','Type','port','PortType','outport');
for k=1:numel(outports), set_param(outports(k),'DataLogging','off'); end
level=['fim_tq_B00/' spec.FaultLevel '/'];
log_([level 'TorqueRatio'],'ratio_before');
log_([level 'Impeller'],'impeller_torque'); log_([level 'Turbine'],'turbine_torque');
save_system('fim_tq_B00'); close_system('fim_tq_B00',0);
copyfile(fullfile(paths.FIMOriginal,'FaultInjector_Master','FInjLib.slx'),fullfile(campaign,'FInjLib.slx'));
cases=struct('ID','B00','Model','fim_tq_B00','FaultBlock','','Delta',0);
for j=1:numel(protocol.cases)
    id=protocol.cases{j}; delta=protocol.deltas(j); name=['fim_tq_' id];
    staging=fullfile(campaign,['generation_' id]); mkdir(staging);
    for folder={'Configuration','FaultInjector_Master','models'}, mkdir(fullfile(staging,folder{1})); end
    for file={'FISingle.m','FCSingle.m','Init_sys_input.m','fault_suite.m','replace_suite.m','fim_arrange_system.m'}
        copyfile(fullfile(paths.FIMPatched,file{1}),staging);
    end
    patchFile=fullfile(paths.Experiment,'dependencies','fim-masked-subsystems.patch');
    [status,output]=system(sprintf('patch --batch --forward -p1 -d "%s" < "%s"',staging,patchFile));
    assert(status==0,'FIM mask traversal patch failed: %s',output);
    copyfile(fullfile(paths.FIMOriginal,'LICENSE'),staging);
    copyfile(fullfile(paths.FIMOriginal,'FaultInjector_Master','FInjLib.slx'),fullfile(staging,'FaultInjector_Master'));
    copyfile(fullfile(paths.FIMOriginal,'Configuration','FIToolInitialization.mat'),fullfile(staging,'Configuration'));
    copyfile(paths.ATModel,fullfile(staging,'models',[name '.mdl']));
    constants=struct(); save(fullfile(staging,'Configuration','AT_constants.mat'),'-struct','constants');
    config=table({['models/' name '.mdl']},{'AT_constants.mat'},{'.'},{'faults.csv'}, ...
        'VariableNames',{'model','constants_thresholds','fault_injector_folder','fault_list'});
    faults=table(string(spec.FaultLevel),string(spec.FaultSource),"NA","NA","Bias/Offset", ...
        'VariableNames',{'level_final','Src_or_InportName','Dst_or_OutportName','ParentBlock','Faulttype_ft'});
    enabled=table(1,-delta,5,"Infinite time","NA","NA", ...
        'VariableNames',{'FaultBlock_Num','Faultvalue_fv','FaultOccurenceTime_fot','FaultEffect_fe','Fault Duration_fd','Fault Operator Number_fo'});
    writetable(config,fullfile(staging,'Configuration','config.csv'));
    writetable(faults,fullfile(staging,'Configuration','faults.csv'));
    writetable(enabled,fullfile(staging,'Configuration','enable.csv'));
    cd(staging); addpath(staging);
    clear FISingle FCSingle Init_sys_input fault_suite replace_suite fim_arrange_system
    FISingle('config.csv','fault_table');
    ft=readtable(fullfile(staging,'fault_table','Fault_table.xls'));
    assert(height(ft)==1,'Expected exactly one FIM injection.');
    FCSingle('config.csv','fault_table','enable.csv');
    mutant=[name '_copy']; block=[char(ft{1,3}) '/' char(ft{1,2})];
    relative=char(extractAfter(string(block),strlength(mutant)+1));
    ph=get_param(block,'PortHandles');
    src=get_param(get_param(ph.Inport(1),'Line'),'SrcPortHandle');
    dst=get_param(get_param(ph.Outport(1),'Line'),'DstPortHandle');
    assert(strcmp(get_param(src,'Parent'),[mutant '/' spec.FaultLevel '/' spec.FaultSource]));
    assert(isscalar(dst) && strcmp(get_param(dst,'Parent'),[mutant '/' spec.FaultLevel '/Turbine']));
    assert(get_param(dst,'PortNumber')==2);
    assert(str2double(get_param([block '/Fault value'],'Value'))==-delta);
    assert(strcmp(get_param(mutant,'Solver'),'ode5') && str2double(get_param(mutant,'FixedStep'))==.01);
    set_param(mutant,'SimulationMode','normal','StopTime','30');
    ports=find_system(mutant,'SearchDepth',1,'BlockType','Inport'); assert(numel(ports)==2);
    for k=1:numel(ports), set_param(ports{k},'Interpolate','off','SampleTime','5'); end
    outports=find_system(mutant,'FindAll','on','LookUnderMasks','all','Type','port','PortType','outport');
    for k=1:numel(outports), set_param(outports(k),'DataLogging','off'); end
    level=[mutant '/' spec.FaultLevel '/'];
    log_([level 'TorqueRatio'],'ratio_before'); log_(block,'ratio_after');
    log_([level 'Impeller'],'impeller_torque'); log_([level 'Turbine'],'turbine_torque');
    save_system(mutant,fullfile(plants,[name '.slx'])); close_system(name,0);
    close_system('FInjLib',0); cd(oldDir); path(oldPath); warning(oldWarning); addpath(paths.ModelData);
    cases(j+1)=struct('ID',id,'Model',name,'FaultBlock',relative,'Delta',delta); %#ok<AGROW>
    fprintf('PREPARED %s: native FIM Offset=%g\n',id,-delta);
end
writetable(struct2table(cases),fullfile(campaign,'fault_catalog.csv'));
prepare_fim_torque_comparison(campaign);
end

function log_(block,name)
p=get_param(block,'PortHandles');
set_param(p.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name);
end

function restore_(directory,oldPath,oldWarning)
cd(directory); path(oldPath); warning(oldWarning);
end

function runDirectory = run_fim_torque_acceleration(stage, runDirectory)
%RUN_FIM_TORQUE_ACCELERATION FIM-generated internal fault, six fixed inputs.
% Stages: all (default), prepare, baseline, faults, report.
% Never modifies the source model, previous runs, or Falsify core.
if nargin<1, stage='all'; end
assert(ismember(stage,{'all','prepare','baseline','faults','report'}));
paths=fim_paths(); spec=fim_torque_spec(); suite=fim_torque_inputs(spec);
oldPath=path; oldDir=pwd; oldWarning=warning;
owned=find_system('type','block_diagram');
assert(~any(startsWith(string(owned),'fim_tq_') | string(owned)=="FInjLib"), ...
    'Save and close fim_tq_* models and FInjLib manually before running.');
cleanup=onCleanup(@()restore_(owned,oldDir,oldPath,oldWarning)); %#ok<NASGU>
addpath(paths.ModelData,fullfile(paths.Repo,'s-taliro','dp_taliro'));
if nargin<2 || isempty(runDirectory)
    assert(ismember(stage,{'all','prepare'}),'Start with prepare or all.');
    parent=fullfile(paths.Repo,'results','fim','torque_acceleration');
    if ~isfolder(parent), mkdir(parent); end
    runDirectory=tempname(parent); mkdir(runDirectory);
    for name={'models','traces','checks','code_snapshot'}, mkdir(fullfile(runDirectory,name{1})); end
    [status,commit]=system(sprintf('git -C "%s" rev-parse HEAD',paths.Repo)); assert(status==0);
    manifest=struct('CreatedAt',char(datetime('now','TimeZone','UTC')), ...
        'BaseCommit',strtrim(commit),'MATLAB',version,'Spec',spec, ...
        'Source',paths.ATModel,'SourceSHA256',sha_(paths.ATModel), ...
        'ModelDataSHA256',sha_(fullfile(paths.ModelData,'sldemo_autotrans_data.mat')), ...
        'Versions',jsondecode(fileread(fullfile(paths.Experiment,'dependencies','versions.json'))));
    for name={'fim_torque_spec','fim_torque_inputs','fim_torque_monitor','run_fim_torque_acceleration'}
        file=which(name{1}); copyfile(file,fullfile(runDirectory,'code_snapshot'));
    end
    copyfile(fullfile(paths.Experiment,'python','audit_torque_acceleration.py'), ...
        fullfile(runDirectory,'code_snapshot'));
    patchFile=fullfile(paths.Experiment,'dependencies','fim-masked-subsystems.patch');
    copyfile(patchFile,fullfile(runDirectory,'code_snapshot'));
    manifest.MaskedSubsystemPatchSHA256=sha_(patchFile);
    save(fullfile(runDirectory,'protocol.mat'),'manifest','spec','suite');
    json_(fullfile(runDirectory,'manifest.json'),manifest);
    rows=table();
    for k=1:numel(suite)
        u=suite(k).U;
        r=table(repmat(string(suite(k).ID),7,1),u(:,1),u(:,2),u(:,3), ...
            'VariableNames',{'Input','TimeSeconds','ThrottlePercent','Brake'});
        rows=[rows;r]; %#ok<AGROW>
    end
    writetable(rows,fullfile(runDirectory,'inputs.csv'));
else
    runDirectory=char(java.io.File(runDirectory).getCanonicalPath());
    x=load(fullfile(runDirectory,'protocol.mat'));
    assert(isequaln(spec,x.spec),'Protocol changed; start a new run.');
    manifest=x.manifest;
    for name={'fim_torque_spec','fim_torque_inputs','fim_torque_monitor','run_fim_torque_acceleration'}
        assert(strcmp(sha_(which(name{1})),sha_(fullfile(runDirectory,'code_snapshot',[name{1} '.m']))), ...
            'Source code changed; start a new run rather than mixing implementations.');
    end
end
fprintf('TORQUE_RUN=%s\n',runDirectory);
assert(strcmp(manifest.SourceSHA256,sha_(paths.ATModel)));
if ismember(stage,{'all','prepare'}), prepare_(paths,runDirectory,spec); end
x=load(fullfile(runDirectory,'cases.mat')); cases=x.cases;
addpath(fullfile(runDirectory,'models'));
load_system(fullfile(runDirectory,'FInjLib.slx')); set_param('FInjLib','Lock','off');
if ismember(stage,{'all','baseline'})
    normal=cell(1,numel(suite)); peaks=zeros(1,numel(suite)); atFault=zeros(size(peaks));
    for k=1:numel(suite)
        normal{k}=run_or_load_(runDirectory,cases(1),suite(k),spec);
        tr=normal{k}; peaks(k)=max(tr.Y(tr.T<=spec.AccelerationDeadline+1e-10,2));
        atFault(k)=max(tr.Y(tr.T<=spec.FaultTime+1e-10,2));
        assert(all(ismember(tr.Y(:,3),spec.GearValues)));
    end
    % This file is frozen before the first faulty simulation.
    target=struct('DeadlineSeconds',spec.AccelerationDeadline, ...
        'TargetSpeedMPH',floor((min(peaks)-spec.BaselineClearanceMPH)/ ...
            spec.TargetRoundingMPH)*spec.TargetRoundingMPH, ...
        'Formula',spec.AccelerationFormulaTemplate, ...
        'Selection','floor((min of six normal peak speeds by deadline - 1 mph)/1 mph)*1 mph', ...
        'NormalPeaksMPH',peaks,'NormalInputs',{spec.InputIDs}, ...
        'FrozenAt',char(datetime('now','TimeZone','UTC')), ...
        'Scope','Calibrated on six normal inputs only; not an all-input guarantee.');
    assert(target.TargetSpeedMPH>max(atFault), ...
        'Target was reached before fault onset; review the normal-only protocol.');
    file=fullfile(runDirectory,'target.json');
    if isfile(file)
        saved=jsondecode(fileread(file)); assert(saved.TargetSpeedMPH==target.TargetSpeedMPH);
    else
        json_(file,target);
    end
    for k=1:numel(suite)
        m=fim_torque_monitor(normal{k}.T,normal{k}.Y,target,spec);
        assert(m.Pass && m.AccelerationRhoMPH>=spec.BaselineClearanceMPH);
    end
    fprintf('FROZEN TARGET: reach %.0f mph by %.0f seconds; normal minimum peak %.9f mph\n', ...
        target.TargetSpeedMPH,target.DeadlineSeconds,min(peaks));
end
if ismember(stage,{'all','faults'})
    assert(isfile(fullfile(runDirectory,'target.json')),'Run baseline before faults.');
    target=jsondecode(fileread(fullfile(runDirectory,'target.json')));
    for j=2:numel(cases)
        for k=1:numel(suite)
            base=load(fullfile(runDirectory,'traces',['B00_' suite(k).ID '.mat']),'trace');
            trace=run_or_load_(runDirectory,cases(j),suite(k),spec);
            assert(isequal(trace.U,base.trace.U) && isequal(trace.T,base.trace.T));
            before=trace.T<spec.FaultTime-1e-10;
            assert(max(abs(trace.Y(before,:)-base.trace.Y(before,:)),[],'all')<spec.ReplayTolerance);
            b=fim_torque_monitor(base.trace.T,base.trace.Y,target,spec); assert(b.Pass);
            % A disabled FIM model must reproduce the normal system, not just its output offset.
            checkFile=fullfile(runDirectory,'checks',[cases(j).ID '_' suite(k).ID '_off.mat']);
            if ~isfile(checkFile)
                off=simulate_(cases(j),suite(k).U,spec,false);
                offError=max(abs(off.Y-base.trace.Y),[],'all');
                assert(offError<spec.ReplayTolerance);
                save(checkFile,'off','offError');
            end
        end
    end
end
if ismember(stage,{'all','baseline','faults','report'})
    report_(runDirectory,cases,suite,spec);
end
assert(strcmp(manifest.SourceSHA256,sha_(paths.ATModel)),'Official model changed.');
fprintf('COMPLETE %s: %s\n',stage,runDirectory);
end

function prepare_(paths,runDir,spec)
assert(~isfile(fullfile(runDir,'cases.mat')),'Models already prepared; use baseline/faults/report.');
models=fullfile(runDir,'models');
copyfile(fullfile(paths.FIMOriginal,'FaultInjector_Master','FInjLib.slx'),fullfile(runDir,'FInjLib.slx'));
copyfile(paths.ATModel,fullfile(models,'fim_tq_B00.mdl'));
load_system(fullfile(models,'fim_tq_B00.mdl'));
configure_('fim_tq_B00',spec,''); save_system('fim_tq_B00'); close_system('fim_tq_B00',0);
cases=struct('ID','B00','Model','fim_tq_B00','FaultBlock','','Delta',0);
for j=1:numel(spec.Deltas)
    id=spec.CaseIDs{j+1}; name=['fim_tq_' id];
    staging=fullfile(runDir,['generation_' id]); mkdir(staging);
    for folder={'Configuration','FaultInjector_Master','models'}, mkdir(fullfile(staging,folder{1})); end
    for file={'FISingle.m','FCSingle.m','Init_sys_input.m','fault_suite.m','replace_suite.m','fim_arrange_system.m'}
        copyfile(fullfile(paths.FIMPatched,file{1}),staging);
    end
    % Additional, recorded adaptation: FIM's default find_system skips masks.
    patchFile=fullfile(paths.Experiment,'dependencies','fim-masked-subsystems.patch');
    [patchStatus,patchOutput]=system(sprintf('patch --batch --forward -p1 -d "%s" < "%s"',staging,patchFile));
    assert(patchStatus==0,'FIM mask traversal patch failed: %s',patchOutput);
    copyfile(fullfile(paths.FIMOriginal,'LICENSE'),staging);
    copyfile(fullfile(paths.FIMOriginal,'FaultInjector_Master','FInjLib.slx'),fullfile(staging,'FaultInjector_Master'));
    copyfile(fullfile(paths.FIMOriginal,'Configuration','FIToolInitialization.mat'),fullfile(staging,'Configuration'));
    copyfile(paths.ATModel,fullfile(staging,'models',[name '.mdl']));
    constants=struct(); save(fullfile(staging,'Configuration','AT_constants.mat'),'-struct','constants');
    config=table({['models/' name '.mdl']},{'AT_constants.mat'},{'.'},{'faults.csv'}, ...
        'VariableNames',{'model','constants_thresholds','fault_injector_folder','fault_list'});
    % Source selection is intentional: Turbine has TWO incoming lines.
    faults=table(string(spec.FaultLevel),string(spec.FaultSource),"NA","NA",string(spec.FaultType), ...
        'VariableNames',{'level_final','Src_or_InportName','Dst_or_OutportName','ParentBlock','Faulttype_ft'});
    enabled=table(1,-spec.Deltas(j),spec.FaultTime,"Infinite time","NA","NA", ...
        'VariableNames',{'FaultBlock_Num','Faultvalue_fv','FaultOccurenceTime_fot','FaultEffect_fe','Fault Duration_fd','Fault Operator Number_fo'});
    writetable(config,fullfile(staging,'Configuration','config.csv'));
    writetable(faults,fullfile(staging,'Configuration','faults.csv'));
    writetable(enabled,fullfile(staging,'Configuration','enable.csv'));
    previous=pwd; previousPath=path; previousWarning=warning;
    if bdIsLoaded('FInjLib'), close_system('FInjLib',0); end
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
    assert(isscalar(dst) && strcmp(get_param(dst,'Parent'), ...
        [mutant '/' spec.FaultLevel '/' spec.FaultDestination]));
    assert(get_param(dst,'PortNumber')==spec.FaultDestinationPort);
    assert(str2double(get_param([block '/Fault value'],'Value'))==-spec.Deltas(j));
    configure_(mutant,spec,relative);
    save_system(mutant,fullfile(models,[name '.slx'])); close_system(name,0);
    close_system('FInjLib',0); cd(previous); path(previousPath); warning(previousWarning);
    cases(j+1)=struct('ID',id,'Model',name,'FaultBlock',relative,'Delta',spec.Deltas(j)); %#ok<AGROW>
    fprintf('PREPARED %s: TorqueRatio -> FIM offset %g -> Turbine port 2\n',id,-spec.Deltas(j));
end
save(fullfile(runDir,'cases.mat'),'cases');
writetable(struct2table(cases),fullfile(runDir,'fault_catalog.csv'));
end

function configure_(model,spec,faultBlock)
assert(strcmp(get_param(model,'Solver'),spec.Solver));
assert(str2double(get_param(model,'FixedStep'))==spec.FixedStep);
assert(strcmp(get_param([model '/Engine/Integrator'],'LimitOutput'),'on'));
assert(str2double(get_param([model '/Engine/Integrator'],'LowerSaturationLimit'))==600);
assert(str2double(get_param([model '/Engine/Integrator'],'UpperSaturationLimit'))==6000);
set_param(model,'SimulationMode','normal','StopTime',num2str(spec.StopTime));
ports=find_system(model,'SearchDepth',1,'BlockType','Inport'); assert(numel(ports)==2);
for k=1:numel(ports), set_param(ports{k},'Interpolate','off','SampleTime',num2str(spec.SampleTime)); end
% Disable old logs only in the derived model; log the exact internal signals used.
outports=find_system(model,'FindAll','on','LookUnderMasks','all','Type','port','PortType','outport');
for k=1:numel(outports), set_param(outports(k),'DataLogging','off'); end
level=[model '/' spec.FaultLevel '/'];
log_([level 'TorqueRatio'],'ratio_before');
log_([level 'Impeller'],'impeller_torque');
log_([level 'Turbine'],'turbine_torque');
if ~isempty(faultBlock), log_([model '/' faultBlock],'ratio_after'); end
end

function log_(block,name)
p=get_param(block,'PortHandles');
set_param(p.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name);
end

function trace=run_or_load_(runDir,c,input,spec)
file=fullfile(runDir,'traces',[c.ID '_' input.ID '.mat']);
if isfile(file)
    x=load(file,'trace'); trace=x.trace; assert(isequal(trace.U,input.U));
    fprintf('RESUME %s %s\n',c.ID,input.ID); return;
end
trace=simulate_(c,input.U,spec,true);
save(file,'trace','input');
table_=array2table([trace.T trace.AppliedU trace.Y trace.RatioBefore trace.RatioAfter ...
    trace.ImpellerTorque trace.TurbineTorque], ...
    'VariableNames',{'TimeSeconds','ThrottlePercent','Brake','RPM','SpeedMPH','Gear', ...
    'TorqueRatioBefore','TorqueRatioAfter','ImpellerTorque','TurbineTorque'});
writetable(table_,fullfile(runDir,'traces',[c.ID '_' input.ID '.csv']));
fprintf('SIMULATED %s %s: speed20=%.6f, speed30=%.6f mph, %.3fs wall time\n', ...
    c.ID,input.ID,trace.Y(round(spec.AccelerationDeadline/spec.FixedStep)+1,2), ...
    trace.Y(end,2),trace.ElapsedSeconds);
end

function trace=simulate_(c,u,spec,enabled)
assert(isequal(u(:,1),(0:spec.SampleTime:spec.StopTime)'));
assert(all(isfinite(u),'all') && all(u(:,3)==0));
assert(all(u(:,2)>=60 & u(:,2)<=100) && isequal(u(end,2:3),u(end-1,2:3)));
load_system(c.Model);
in=Simulink.SimulationInput(c.Model); in=in.setVariable('u',u);
in=in.setModelParameter('SimulationMode','normal','StopTime',num2str(spec.StopTime), ...
    'LoadExternalInput','on','ExternalInput','u','SaveTime','on','TimeSaveName','tout', ...
    'SaveOutput','on','OutputSaveName','yout','SaveFormat','Array', ...
    'SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
if ~isempty(c.FaultBlock)
    in=in.setBlockParameter([c.Model '/' c.FaultBlock '/Enable_flag'],'Value',num2str(enabled));
end
started=tic; out=sim(in); elapsed=toc(started);
trace=struct('T',out.tout,'Y',out.yout(:,[2 1 3]),'U',u,'ElapsedSeconds',elapsed, ...
    'Case',c.ID,'Delta',c.Delta,'Enabled',enabled);
grid=(0:spec.FixedStep:spec.StopTime)';
assert(isequal(size(trace.T),size(grid)) && max(abs(trace.T-grid))<1e-10);
assert(all(isfinite(trace.Y),'all'),'Nonfinite output is not a counterexample.');
trace.AppliedU=interp1(u(:,1),u(:,2:3),trace.T,'previous','extrap');
trace.RatioBefore=signal_(out,'ratio_before',trace.T);
if isempty(c.FaultBlock), trace.RatioAfter=trace.RatioBefore;
else, trace.RatioAfter=signal_(out,'ratio_after',trace.T); end
trace.ImpellerTorque=signal_(out,'impeller_torque',trace.T);
trace.TurbineTorque=signal_(out,'turbine_torque',trace.T);
active=trace.T>=spec.FaultTime-1e-10 & enabled;
expected=trace.RatioBefore-c.Delta*active;
trace.InjectionError=max(abs(trace.RatioAfter-expected));
trace.TorqueProductError=max(abs(trace.TurbineTorque-trace.ImpellerTorque.*trace.RatioAfter));
assert(trace.InjectionError<spec.InjectionTolerance);
assert(trace.TorqueProductError<spec.ReplayTolerance);
assert(all(trace.RatioAfter>0),'Nonpositive torque ratio is outside this pilot.');
end

function values=signal_(out,name,t)
v=out.logsout.get(name).Values;
assert(numel(v.Time)==numel(t) && max(abs(v.Time(:)-t))<1e-10, ...
    'Unexpected logging grid; do not silently interpolate internal signals.');
values=double(v.Data(:)); assert(all(isfinite(values)));
end

function report_(runDir,cases,suite,spec)
file=fullfile(runDir,'target.json'); if ~isfile(file), return; end
target=jsondecode(fileread(file)); rows=struct([]);
for j=1:numel(cases)
    for k=1:numel(suite)
        file=fullfile(runDir,'traces',[cases(j).ID '_' suite(k).ID '.mat']);
        if ~isfile(file), continue; end
        x=load(file,'trace'); tr=x.trace;
        m=fim_torque_monitor(tr.T,tr.Y,target,spec);
        b=load(fullfile(runDir,'traces',['B00_' suite(k).ID '.mat']),'trace');
        bm=fim_torque_monitor(b.trace.T,b.trace.Y,target,spec);
        row=struct('Case',cases(j).ID,'Input',suite(k).ID,'Delta',cases(j).Delta, ...
            'TargetSpeedMPH',target.TargetSpeedMPH,'DeadlineSeconds',target.DeadlineSeconds, ...
            'AccelerationRhoMPH',m.AccelerationRhoMPH,'AccelerationPass',m.AccelerationPass, ...
            'GearRangePass',m.GearRangePass,'GearDiscretePass',m.GearDiscretePass, ...
            'GearRho',m.GearRho,'Pass',m.Pass, ...
            'FaultInducedViolation',j>1 && bm.Pass && ~m.Pass, ...
            'FirstReachSeconds',m.FirstReachSeconds,'SpeedAtDeadlineMPH',m.SpeedAtDeadlineMPH, ...
            'SpeedAt30MPH',m.SpeedAt30MPH, ...
            'SpeedLossAtDeadlineMPH',bm.SpeedAtDeadlineMPH-m.SpeedAtDeadlineMPH, ...
            'MinRPM',m.MinRPM,'MaxRPM',m.MaxRPM,'MinGear',m.MinGear,'MaxGear',m.MaxGear, ...
            'MinimumTorqueRatio',min(tr.RatioAfter),'InjectionError',tr.InjectionError, ...
            'TorqueProductError',tr.TorqueProductError, ...
            'AccelerationMonitorError',m.AccelerationMonitorError,'GearMonitorError',m.GearMonitorError, ...
            'ElapsedSeconds',tr.ElapsedSeconds);
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    end
end
writetable(struct2table(rows),fullfile(runDir,'summary.csv'));
end

function restore_(owned,oldDir,oldPath,oldWarning)
now=find_system('type','block_diagram');
for k=1:numel(now)
    if ~ismember(now{k},owned), try, close_system(now{k},0); catch, end, end
end
cd(oldDir); path(oldPath); warning(oldWarning);
end

function value=sha_(file)
fid=fopen(file,'rb'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid), md.update(fread(fid,1024*1024,'*uint8')); end
value=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2)',1,[]));
end

function json_(file,value)
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

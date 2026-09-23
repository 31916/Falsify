function runDirectory = run_fim_at_experiments(stage, runDirectory, options)
%RUN_FIM_AT_EXPERIMENTS Reproducible FIM single-fault AT experiment.
% Stages: prepare, exp1, pilot, exp2, report, all. Resume with a run directory.
% Derived models/traces stay in ignored results/fim/runs; sources stay intact.
if nargin < 1, stage = 'all'; end
if nargin < 3, options=struct(); end
repo = fileparts(mfilename('fullpath'));
workspace = fileparts(repo);
spec = fim_at_spec();
originalPath = path; originalDir = pwd; originalWarnings = warning;
ownedBefore = find_system('type','block_diagram');
conflicts=ownedBefore(startsWith(string(ownedBefore),["fim_at_","fim_rl_"]) | ...
    ismember(string(ownedBefore),["FInjLib","autotrans_mod04"]));
assert(isempty(conflicts),'Close these models manually before running: %s',strjoin(conflicts,', '));
cleanup = onCleanup(@() restore_(originalDir, originalPath, originalWarnings, ownedBefore)); %#ok<NASGU>
addpath(repo, fullfile(repo,'arch2025_generated'));
addpath(fullfile(repo,'s-taliro','dp_taliro'),fullfile(repo,'s-taliro','monitor'));
addpath(fullfile(workspace,'Examples','R2026a','simulink_automotive', ...
    'ModelingAnAutomaticTransmissionControllerExample'));
if nargin < 2 || isempty(runDirectory)
    assert(ismember(stage,{'all','prepare'}),'A run directory is required for this stage.');
    parent = fullfile(repo,'results','fim','runs');
    if ~isfolder(parent), mkdir(parent); end
    runDirectory = tempname(parent); mkdir(runDirectory);
    source = fullfile(workspace,'ARCH-COMP','ARCH-COMP-full','models','FALS','transmission','Autotrans_shift.mdl');
    manifest = struct('CreatedAt',char(datetime('now')),'MATLAB',version, ...
        'Source',source,'SourceSHA256',sha_(source), ...
        'FIMCommit','a110acf2b718eab4cdf65f938203f60009fa0510', ...
        'Spec',spec,'InputSemantics','piecewise constant; ZOH; changes every 5 s', ...
        'Scope','Preliminary bounded search, not a formal proof or algorithm comparison');
    json_(fullfile(runDirectory,'manifest.json'),manifest);
    writetable(spec.Faults,fullfile(runDirectory,'fault_catalog.csv'));
    save(fullfile(runDirectory,'protocol.mat'),'manifest','spec');
else
    runDirectory=char(java.io.File(runDirectory).getCanonicalPath());
    saved = load(fullfile(runDirectory,'protocol.mat'));
    assert(isequaln(saved.spec,spec),'Protocol changed; start a fresh run.');
    manifest = saved.manifest;
end
fprintf('FIM RUN: %s\n',runDirectory);
if ismember(stage,{'all','prepare'})
    prepare_(repo,workspace,runDirectory,spec,manifest);
end
cases = load(fullfile(runDirectory,'cases.mat')); cases = cases.cases;
addpath(fullfile(runDirectory,'models'));
load_system(fullfile(runDirectory,'FInjLib.slx')); set_param('FInjLib','Lock','off');
if strcmp(stage,'external')
    k=find(strcmp({cases.ID},options.Case)); assert(isscalar(k),'Unknown case.');
    file=char(java.io.File(options.File).getCanonicalPath());
    assert(startsWith(file,[runDirectory filesep]) && ~isfile(file));
    u=options.U; trace=simulate_(cases(k),u,spec);
    if k==1, normal=trace; else, normal=simulate_(cases(1),u,spec); end
    assert(normal.Rho>0 && trace.InjectionError<1e-7);
    save(file,'u','trace','normal');
end
if strcmp(stage,'interfaces')
    for k=1:numel(cases)
        load_system(cases(k).Model); configurePlant_(cases(k).Model);
        save_system(cases(k).Model); close_system(cases(k).Model,0);
    end
end
if strcmp(stage,'wrappers')
    load_system(fullfile(repo,'autotrans','autotrans_mod04.slx'));
    for k=1:numel(cases), wrapper_(fullfile(runDirectory,'models'),cases(k),spec); end
end
if ismember(stage,{'all','exp1'}), experiment1_(runDirectory,cases,spec); end
if ismember(stage,{'all','exp2','pilot'})
    experiment2_(repo,runDirectory,cases,spec,strcmp(stage,'pilot'));
end
if strcmp(stage,'additional')
    assert(isfield(options,'Algorithms') && isfield(options,'MaxEpisodes') && isfield(options,'Folder'));
    assert(all(ismember(options.Algorithms,{'RAND','ACER','A3C','DDQN'})));
    assert(options.MaxEpisodes>=1 && options.MaxEpisodes==fix(options.MaxEpisodes));
    assert(~isempty(regexp(options.Folder,'^additional_[A-Za-z0-9_]+$','once')));
    experiment2_(repo,runDirectory,cases,spec,false,options);
end
if ismember(stage,{'all','exp1','exp2','report'}), report_(runDirectory); end
assert(strcmp(manifest.SourceSHA256,sha_(manifest.Source)),'Official source changed!');
fprintf('FIM stage %s complete: %s\n',stage,runDirectory);
end

function prepare_(repo,workspace,runDir,spec,manifest)
modelDir = fullfile(runDir,'models'); mkdir(modelDir);
vendor = fullfile(workspace,'FIM','vendor','fimtool');
compat = fullfile(workspace,'FIM','work','fimtool-r2026a');
copyfile(fullfile(vendor,'FaultInjector_Master','FInjLib.slx'),fullfile(runDir,'FInjLib.slx'));
assert(~bdIsLoaded('Autotrans_shift'),'Close the official AT model before preparing.');
copyfile(manifest.Source,fullfile(modelDir,'fim_at_B00.mdl'));
load_system(fullfile(modelDir,'fim_at_B00.mdl'));
assert(strcmp(get_param('fim_at_B00/Engine/Integrator','LimitOutput'),'on'));
assert(str2double(get_param('fim_at_B00/Engine/Integrator','LowerSaturationLimit'))==600);
assert(str2double(get_param('fim_at_B00/Engine/Integrator','UpperSaturationLimit'))==6000);
assert(str2double(get_param('fim_at_B00/Engine/Integrator','InitialCondition'))==1000);
configurePlant_('fim_at_B00');
save_system('fim_at_B00'); close_system('fim_at_B00',0);
cases = struct('ID','B00','Model','fim_at_B00','FaultBlock','','Wrapper','fim_rl_B00');
for k=1:height(spec.Faults)
    f=spec.Faults(k,:); id=char(f.ID); name=['fim_at_' id];
    staging=fullfile(runDir,['generation_' id]); mkdir(staging);
    for folder={'Configuration','FaultInjector_Master','models'}, mkdir(fullfile(staging,folder{1})); end
    for file={'FISingle.m','FCSingle.m','Init_sys_input.m','fault_suite.m','replace_suite.m','fim_arrange_system.m'}
        copyfile(fullfile(compat,file{1}),staging);
    end
    % Narrow upstream substring level matching to this exact subsystem.
    % In particular, root /gear must not also select ShiftLogic/gear.
    fn=fullfile(staging,'fault_suite.m'); code=fileread(fn);
    old='contains(block_inform{i}, level_final)';
    assert(numel(strfind(code,old))==1);
    write_(fn,strrep(code,old,'strcmp(block_inform{i}, level_final)'));
    copyfile(fullfile(vendor,'LICENSE'),staging);
    copyfile(fullfile(vendor,'FaultInjector_Master','FInjLib.slx'),fullfile(staging,'FaultInjector_Master'));
    copyfile(fullfile(vendor,'Configuration','FIToolInitialization.mat'),fullfile(staging,'Configuration'));
    copyfile(manifest.Source,fullfile(staging,'models',[name '.mdl']));
    constants=struct(); save(fullfile(staging,'Configuration','AT_constants.mat'),'-struct','constants');
    config=table({['models/' name '.mdl']},{'AT_constants.mat'},{'.'},{'faults.csv'}, ...
        'VariableNames',{'model','constants_thresholds','fault_injector_folder','fault_list'});
    writetable(config,fullfile(staging,'Configuration','config.csv'));
    faults=table(f.Level,"NA",f.Destination,"NA",f.Type, ...
        'VariableNames',{'level_final','Src_or_InportName','Dst_or_OutportName','ParentBlock','Faulttype_ft'});
    writetable(faults,fullfile(staging,'Configuration','faults.csv'));
    enabled=table(1,f.Value,spec.FaultTime,"Infinite time","NA","NA", ...
        'VariableNames',{'FaultBlock_Num','Faultvalue_fv','FaultOccurenceTime_fot','FaultEffect_fe','Fault Duration_fd','Fault Operator Number_fo'});
    writetable(enabled,fullfile(staging,'Configuration','enable.csv'));
    previous=pwd; oldPath=path; oldWarning=warning;
    if bdIsLoaded('FInjLib'), close_system('FInjLib',0); end
    cd(staging); addpath(staging);
    clear FISingle FCSingle Init_sys_input fault_suite replace_suite fim_arrange_system
    FISingle('config.csv','fault_table');
    ft=readtable(fullfile(staging,'fault_table','Fault_table.xls'));
    assert(height(ft)==1,'Expected exactly ONE fault for %s; got %d.',id,height(ft));
    FCSingle('config.csv','fault_table','enable.csv');
    mutant=[name '_copy'];
    faultBlock=[char(ft{1,3}) '/' char(ft{1,2})];
    relative=extractAfter(string(faultBlock),strlength(mutant)+1);
    configurePlant_(mutant);
    save_system(mutant,fullfile(modelDir,[name '.slx']));
    % Save As changes the loaded root name.
    close_system(name,0); close_system('FInjLib',0);
    cd(previous); path(oldPath); warning(oldWarning);
    cases(k+1)=struct('ID',id,'Model',name,'FaultBlock',char(relative),'Wrapper',['fim_rl_' id]); %#ok<AGROW>
    fprintf('PREPARED %s: %s -> %s, %s %g\n',id,char(f.Level),char(f.Destination),char(f.Type),f.Value);
end
save(fullfile(runDir,'cases.mat'),'cases');
load_system(fullfile(runDir,'FInjLib.slx')); set_param('FInjLib','Lock','off');
template=fullfile(repo,'autotrans','autotrans_mod04.slx');
assert(~bdIsLoaded('autotrans_mod04'),'Close autotrans_mod04 before preparing.');
load_system(template);
for k=1:numel(cases), wrapper_(modelDir,cases(k),spec); end
close_system('autotrans_mod04',0);
end

function configurePlant_(model)
set_param(model,'SimulationMode','normal','StopTime','30','ReturnWorkspaceOutputs','on');
assert(strcmp(get_param(model,'Solver'),'ode5'));
assert(str2double(get_param(model,'FixedStep'))==0.01);
inputs=find_system(model,'SearchDepth',1,'BlockType','Inport');
assert(numel(inputs)==2);
% Discrete root inputs update at major 5-second hits, just like the RL
% agent. Continuous external ZOH data alone can change during the ode5
% endpoint stage of the PRECEDING step and cause a spurious replay mismatch.
for k=1:numel(inputs)
    set_param(inputs{k},'Interpolate','off','SampleTime','5');
end
end

function wrapper_(modelDir,c,spec)
src=fullfile(modelDir,[c.Model '.slx']);
if ~isfile(src), src=fullfile(modelDir,[c.Model '.mdl']); end
load_system(src); save_system(c.Model,fullfile(modelDir,[c.Wrapper '.slx']));
m=c.Wrapper;
ins=find_system(m,'SearchDepth',1,'BlockType','Inport');
inputNumbers=cellfun(@(b)str2double(get_param(b,'Port')),ins);
dest=cell(1,2);
for k=1:numel(ins)
    p=inputNumbers(k); ph=get_param(ins{k},'PortHandles');
    lh=get_param(ph.Outport,'Line'); dest{p}=get_param(lh,'DstPortHandle');
    delete_line(lh); delete_block(ins{k});
end
outs=find_system(m,'SearchDepth',1,'BlockType','Outport'); sources=zeros(1,3);
outputNumbers=cellfun(@(b)str2double(get_param(b,'Port')),outs);
for k=1:numel(outs)
    p=outputNumbers(k); ph=get_param(outs{k},'PortHandles');
    lh=get_param(ph.Inport,'Line'); sources(p)=get_param(lh,'SrcPortHandle');
    delete_line(m,sources(p),ph.Inport); delete_block(outs{k});
end
assert(all(sources>0)); % Official output order: speed, RPM, gear.
add_block('autotrans_mod04/RL agent',[m '/RL agent']);
set_param([m '/RL agent'],'System','rl_agent_arch2025_pconst', ...
    'sample_time','5','input_range',mat2str(spec.InputRange),'observation_dimension','3');
add_block('autotrans_mod04/TaLiRo_Monitor',[m '/TaLiRo_Monitor']);
add_block('simulink/Signal Routing/Demux',[m '/Action split'],'Outputs','2');
add_block('simulink/Signal Routing/Mux',[m '/State mux'],'Inputs','3');
add_block('simulink/Math Operations/Bias',[m '/State center'], ...
    'Bias',mat2str(-mean(spec.OutputRange,2)));
add_block('simulink/Math Operations/Gain',[m '/State normalize'], ...
    'Gain',mat2str(2./diff(spec.OutputRange,1,2)), 'Multiplication','Element-wise(K.*u)');
for k=1:3
    names={'RewardOut','StateOut','ActionOut'};
    add_block('simulink/Sinks/Out1',[m '/' names{k}],'Port',num2str(k));
end
add_line(m,'RL agent/1','Action split/1'); add_line(m,'RL agent/1','ActionOut/1');
d=get_param([m '/Action split'],'PortHandles');
for p=1:2, for h=reshape(dest{p},1,[]), add_line(m,d.Outport(p),h); end, end
x=get_param([m '/State mux'],'PortHandles');
order=[2 1 3];
for p=1:3, add_line(m,sources(order(p)),x.Inport(p)); end
add_line(m,'State mux/1','State center/1');
add_line(m,'State center/1','State normalize/1');
add_line(m,'State normalize/1','RL agent/1');
add_line(m,'State normalize/1','TaLiRo_Monitor/1');
add_line(m,'State normalize/1','StateOut/1');
add_line(m,'TaLiRo_Monitor/1','RL agent/2');
add_line(m,'TaLiRo_Monitor/1','RewardOut/1');
set_param(m,'LoadExternalInput','off','SaveFormat','Dataset', ...
    'SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout');
save_system(m); close_system(m,0);
end

function experiment1_(runDir,cases,spec)
folder=fullfile(runDir,'exp1'); if ~isfolder(folder), mkdir(folder); end
suite=inputs_(spec); rows=struct([]);
for j=1:numel(suite)
    baseline=simulate_(cases(1),suite(j).U,spec);
    assert(baseline.Rho>0,'Baseline violated the invariant!');
    for k=1:numel(cases)
        c=cases(k); file=fullfile(folder,[c.ID '_' suite(j).ID '.mat']);
        if isfile(file)
            saved=load(file,'trace','offError','preError','injectionError');
            trace=saved.trace; offError=saved.offError;
            preError=saved.preError; injectionError=saved.injectionError;
        else
        if k==1, trace=baseline; else, trace=simulate_(c,suite(j).U,spec); end
        offError=0; preError=0; injectionError=0;
        if k>1
            off=simulate_(c,suite(j).U,spec,false);
            offError=max(abs(off.Y-baseline.Y),[],'all');
            pre=trace.T<spec.FaultTime-1e-10;
            preError=max(abs(trace.Y(pre,:)-baseline.Y(pre,:)),[],'all');
            assert(offError<1e-7 && preError<1e-7,'Fault OFF or pre-activation mismatch.');
            injectionError=trace.InjectionError;
            assert(injectionError<1e-7,'FIM operation did not match its configured fault.');
        end
        save(file,'trace','baseline','offError','preError','injectionError');
        end
        row=struct('Case',string(c.ID),'Input',string(suite(j).ID), ...
            'Rho',trace.Rho,'Violated',trace.Rho < -spec.Tolerance, ...
            'RPMMinimum',min(trace.Y(:,1)),'RPMMaximum',max(trace.Y(:,1)), ...
            'GearMinimum',min(trace.Y(:,3)),'GearMaximum',max(trace.Y(:,3)), ...
            'FaultOffMaxError',offError,'BeforeFaultMaxError',preError,'InjectionMaxError',injectionError);
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    end
    writetable(struct2table(rows),fullfile(runDir,'experiment1.csv'));
    fprintf('EXP1 completed input %s (%d/%d)\n',suite(j).ID,j,numel(suite));
end
end

function suite=inputs_(spec)
t=(0:5:30)';
values={repmat([0 0],7,1),repmat([100 0],7,1),repmat([0 325],7,1), ...
    repmat([100 325],7,1),repmat([50 0],7,1), ...
    [0 0;20 0;40 0;60 0;80 0;100 0;100 0], ...
    [100 0;100 0;0 325;0 325;100 0;100 0;100 0], ...
    [0 325;100 0;0 325;100 0;0 325;100 0;100 0]};
rng(4101,'twister');
for k=1:4, v=rand(7,2).*[100 325]; v(end,:)=v(end-1,:); values{end+1}=v; end
for j=1:numel(values)
    suite(j)=struct('ID',sprintf('U%02d',j),'U',[t values{j}]); %#ok<AGROW>
    validateInput_(suite(j).U,spec);
end
end

function trace=simulate_(c,u,spec,enabled)
if nargin<4, enabled=true; end
validateInput_(u,spec); load_system(c.Model);
if ~isempty(c.FaultBlock)
    block=[c.Model '/' c.FaultBlock];
    set_param([block '/Enable_flag'],'Value',num2str(enabled));
    ph=get_param(block,'PortHandles');
    for pair={ph.Inport(1),'fim_before';ph.Outport(1),'fim_after'}'
        lh=get_param(pair{1},'Line');
        source=get_param(lh,'SrcPortHandle');
        set_param(source,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',pair{2});
    end
end
in=Simulink.SimulationInput(c.Model);
in=in.setVariable('u',u);
in=in.setModelParameter('SimulationMode','normal','StopTime',num2str(spec.StopTime), ...
    'LoadExternalInput','on','ExternalInput','u','SaveTime','on','TimeSaveName','tout', ...
    'SaveOutput','on','OutputSaveName','yout','SaveFormat','Array', ...
    'SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
out=sim(in); trace.T=out.tout; trace.Y=out.yout(:,[2 1 3]); trace.U=u;
assert(numel(trace.T)==3001 && abs(trace.T(end)-30)<1e-10);
[trace.Rho,trace.ClauseMargins]=robustness_(trace.Y);
trace.InjectionError=0;
if ~isempty(c.FaultBlock)
    before=out.logsout.get('fim_before').Values; after=out.logsout.get('fim_after').Values;
    f=spec.Faults(strcmp(spec.Faults.ID,c.ID),:);
    if isequal(before.Time,after.Time)
        aligned=double(before.Data);
    else
        % Stateflow gear is discrete; FIM's Step can add logging instants.
        % Hold the latest gear value, never linearly interpolate gears.
        assert(f.Destination=="gear",'Unexpected continuous logging-grid mismatch.');
        [bt,bi]=unique(before.Time,'last');
        aligned=interp1(bt,double(before.Data(bi)),after.Time,'previous','extrap');
    end
    expected=aligned; active=enabled & after.Time>=spec.FaultTime-1e-10;
    switch f.Type
        case "Bias/Offset", expected(active)=expected(active)+f.Value;
        case "Negate", expected(active)=-expected(active);
        case "Stuck-at 0", expected(active)=0;
    end
    trace.InjectionError=max(abs(expected-double(after.Data)),[],'all');
    trace.Injected=struct('T',after.Time,'Before',aligned,'After',after.Data);
    set_param([block '/Enable_flag'],'Value','1');
end
end

function [rho,margins]=robustness_(y)
assert(all(isfinite(y),'all'),'Nonfinite trajectory is not an STL violation.');
margins=min([y(:,1)-599,6001-y(:,1),y(:,3)-0.5,4.5-y(:,3)],[],1);
rho=min(margins./[3000 3000 1.5 1.5]);
end

function validateInput_(u,spec)
assert(size(u,2)==3 && all(isfinite(u),'all') && u(1,1)==0 && u(end,1)==spec.StopTime);
assert(all(diff(u(:,1))>0));
assert(all(u(:,2:3)>=spec.InputRange(:,1)'-1e-9,'all'));
assert(all(u(:,2:3)<=spec.InputRange(:,2)'+1e-9,'all'));
changed=[true;any(abs(diff(u(:,2:3)))>1e-9,2)];
assert(all(abs(u(changed,1)/spec.SampleTime-round(u(changed,1)/spec.SampleTime))<1e-8), ...
    'Inputs changed outside the 5-second control grid.');
end

function experiment2_(repo,runDir,cases,spec,pilot,options)
additional=nargin>=6;
if additional
    outputRoot=fullfile(runDir,options.Folder);
    if ~isfolder(outputRoot), mkdir(outputRoot); end
    protocolFile=fullfile(outputRoot,'protocol.mat');
    if isfile(protocolFile)
        previous=load(protocolFile,'options');
        assert(isequaln(previous.options,options),'Additional experiment protocol changed.');
    else
        save(protocolFile,'options','spec');
        json_(fullfile(outputRoot,'protocol.json'),struct('Options',options,'Spec',spec));
        snapshot=fullfile(outputRoot,'code_snapshot'); mkdir(snapshot);
        for name={'run_fim_at_experiments.m','fim_at_spec.m','falsify.m','driver.py'}
            copyfile(fullfile(repo,name{1}),snapshot);
        end
    end
else
    outputRoot=runDir;
end
env=pyenv;
python=fullfile(repo,'.venv-falsify','bin','python');
if env.Status=="NotLoaded", pyenv('Version',python,'ExecutionMode','InProcess'); end
assert(strcmp(string(pyenv().Executable),string(python)));
insert(py.sys.path,int32(0),repo); py.importlib.import_module('driver');
numpyConfig=py.importlib.import_module('numpy.__config__');
numpyModule=py.importlib.import_module('numpy');
runtime=struct('Python',char(py.sys.version),'PythonExecutable',python, ...
    'NumPy',char(py.getattr(numpyModule,'__version__')),'NumPyFile',char(py.getattr(numpyModule,'__file__')), ...
    'BLASBuild',char(py.str(numpyConfig.get_info('openblas64__info'))), ...
    'FalsifySHA256',sha_(fullfile(repo,'falsify.m')), ...
    'DriverSHA256',sha_(fullfile(repo,'driver.py')), ...
    'RunnerSHA256',sha_(mfilename('fullpath')+".m"));
json_(fullfile(outputRoot,'runtime.json'),runtime);
folder=fullfile(outputRoot,'exp2'); if ~isfolder(folder), mkdir(folder); end
if pilot, indices=[1 2]; algorithms={'RAND'}; seeds=spec.Seeds(1); else
    indices=1:numel(cases); algorithms=spec.Algorithms; seeds=spec.Seeds;
end
maxEpisodes=spec.MaxEpisodes;
if additional, algorithms=options.Algorithms; maxEpisodes=options.MaxEpisodes; end
for k=indices
    c=cases(k);
    for a=1:numel(algorithms)
        for seed=seeds
            tag=sprintf('%s_%s_%d',c.ID,algorithms{a},seed);
            if pilot, tag=['pilot_' tag]; end
            file=fullfile(folder,[tag '.mat']);
            if isfile(file), fprintf('RESUME skip %s\n',tag); continue; end
            rng(seed,'twister'); py.random.seed(int32(seed)); py.numpy.random.seed(int32(seed));
            config=struct('maxEpisodes',maxEpisodes,'useModelSolverSettings',true, ...
                'agentName','/RL agent','option',algorithms{a},'mdl',c.Wrapper, ...
                'input_range',spec.InputRange,'output_range',spec.OutputRange, ...
                'alpha',0,'sampleTime',spec.SampleTime,'stopTime',spec.StopTime, ...
                'targetFormula',spec.Formula,'monitoringFormula',spec.Formula,'preds',spec.Preds, ...
                'objectiveSource','independent FIM plant replay');
            if pilot, config.maxEpisodes=1; end
            candidateParent=fullfile(folder,tag);
            if ~isfolder(candidateParent), mkdir(candidateParent); end
            candidateFolder=tempname(candidateParent); mkdir(candidateFolder);
            config.episodeEvaluator=@(yout) evaluate_(yout,c,cases(1),spec,candidateFolder);
            cd(repo); addpath(repo,fullfile(runDir,'models'));
            [episodes,elapsed,rho,~,bestYout,bestEvaluation,history]=falsify(config);
            addpath(repo); cd(repo);
            assert(max(abs(history.ObjectiveRobustness-history.WrapperRobustness))<1e-9, ...
                'Offline analytic and dp_taliro robustness disagree.');
            result=struct('Case',string(c.ID),'Algorithm',string(algorithms{a}),'Seed',seed, ...
                'Episodes',episodes,'Seconds',elapsed,'Rho',rho, ...
                'Violated',rho < -spec.Tolerance,'BaselineRho',bestEvaluation.BaselineRho, ...
                'ReplayMaxError',bestEvaluation.ReplayMaxError,'CandidateDirectory',string(candidateFolder));
            if additional
                result.MaxEpisodes=maxEpisodes;
                result.LearningUpdates=0;
                module=py.importlib.import_module('driver');
                agent=py.getattr(module,'agent');
                if logical(py.hasattr(agent,'optimizer'))
                    optimizer=py.getattr(agent,'optimizer');
                    result.LearningUpdates=double(py.getattr(optimizer,'t'));
                end
                result.ReplayStartSize=0;
                if strcmp(algorithms{a},'DDQN')
                    updater=py.getattr(agent,'replay_updater');
                    result.ReplayStartSize=double(py.getattr(updater,'replay_start_size'));
                end
            end
            save(file,'result','bestYout','bestEvaluation','history');
            fprintf('EXP2 %s: rho=%g; episodes=%d; replay error=%g\n',tag,rho,episodes,result.ReplayMaxError);
            report_(outputRoot);
        end
    end
end
end

function [rho,e]=evaluate_(yout,c,baseline,spec,candidateFolder)
actions=yout.getElement(3).Values;
t=double(actions.Time(:)); v=double(squeeze(actions.Data));
if size(v,1)~=numel(t), v=v'; end
[t,idx]=unique(t,'last'); v=v(idx,:);
u=[t v]; validateInput_(u,spec);
trace=simulate_(c,u,spec); normal=simulate_(baseline,u,spec);
state=yout.getElement(2).Values; wt=double(state.Time(:)); wy=double(squeeze(state.Data));
if size(wy,1)~=numel(wt), wy=wy'; end
[wt,idx]=unique(wt,'last'); wy=wy(idx,:);
wy=wy.*(diff(spec.OutputRange,1,2)'/2)+mean(spec.OutputRange,2)';
assert(numel(wt)==numel(trace.T) && max(abs(wt-trace.T))<1e-8);
err=max(abs(wy-trace.Y),[],'all');
if err>=1e-5
    modelDir=fileparts(get_param(c.Model,'FileName'));
    save(fullfile(fileparts(modelDir),['replay_mismatch_' c.ID '.mat']), ...
        'u','trace','normal','wt','wy','err');
end
assert(err<1e-5,'FIM:ReplayMismatch','Wrapper and independent FIM replay disagree: %g',err);
assert(normal.Rho>0,'Baseline failed for a generated input.');
assert(trace.InjectionError<1e-7,'Injection mechanism failed.');
rho=trace.Rho;
e=struct('BaselineRho',normal.Rho,'ReplayMaxError',err,'Trace',trace,'Baseline',normal);
episode=1+numel(dir(fullfile(candidateFolder,'episode_*.mat')));
save(fullfile(candidateFolder,sprintf('episode_%03d.mat',episode)), ...
    'u','trace','normal','err');
end

function report_(runDir)
files=dir(fullfile(runDir,'exp2','*.mat')); rows=struct([]);
for k=1:numel(files)
    if startsWith(files(k).name,'pilot_'), continue; end
    x=load(fullfile(files(k).folder,files(k).name),'result');
    if isempty(rows), rows=x.result; else, rows(end+1)=x.result; end %#ok<AGROW>
end
if ~isempty(rows), writetable(struct2table(rows),fullfile(runDir,'experiment2.csv')); end
end

function restore_(oldDir,oldPath,oldWarning,before)
now=find_system('type','block_diagram');
for k=1:numel(now)
    if ~ismember(now{k},before), try, close_system(now{k},0); catch, end, end
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
write_(file,jsonencode(value,'PrettyPrint',true));
end

function write_(file,value)
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',value);
end

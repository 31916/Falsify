function runDirectory = run_fim_rpm_calibration(previousRun,preparedRun)
%RUN_FIM_RPM_CALIBRATION Direct fixed-input simulation, no falsification tools.
% previousRun: historical 12-input experiment; preparedRun: regenerated FIM plants.
% Copies models into a new folder. Never edits either input run.
paths=fim_paths(); spec=fim_at_spec();
cfg=jsondecode(fileread(fullfile(paths.Experiment,'config','rpm_calibration.json')));
assert(spec.StopTime==30 && spec.SampleTime==5 && spec.FaultTime==5);
before=find_system('type','block_diagram');
assert(~any(ismember(before,{'fim_rpmcal_normal','fim_rpmcal_fault','FInjLib'})), ...
    'Close calibration models/FInjLib manually before running.');
oldPath=path; oldDir=pwd; oldWarnings=warning;
cleanup=onCleanup(@()restore_(before,oldPath,oldDir,oldWarnings)); %#ok<NASGU>
parent=fullfile(paths.Repo,'results','fim','calibration');
if ~isfolder(parent), mkdir(parent); end
runDirectory=tempname(parent); mkdir(runDirectory);
folder=fullfile(runDirectory,'models'); mkdir(folder);
baselineFolder=fullfile(runDirectory,'baseline'); mkdir(baselineFolder);
validationFolder=fullfile(runDirectory,'validation'); mkdir(validationFolder);
snapshot=fullfile(runDirectory,'code_snapshot'); mkdir(snapshot);
copyfile(which('run_fim_rpm_calibration'),snapshot);
copyfile(which('fim_at_spec'),snapshot);
copyfile(fullfile(paths.Experiment,'config','rpm_calibration.json'),snapshot);
copyfile(fullfile(paths.Experiment,'python','audit_rpm_calibration.py'),snapshot);
copyfile(fullfile(preparedRun,'FInjLib.slx'),fullfile(runDirectory,'FInjLib.slx'));
normalSource=fullfile(preparedRun,'models','fim_at_B00.mdl');
faultSource=fullfile(preparedRun,'models','fim_at_F01.slx');
assert(isfile(normalSource) && isfile(faultSource));
copyfile(normalSource,fullfile(folder,'fim_rpmcal_normal.mdl'));
copyfile(faultSource,fullfile(folder,'fim_rpmcal_fault.slx'));
sourceManifest=jsondecode(fileread(fullfile(preparedRun,'manifest.json')));
assert(strcmp(sourceManifest.SourceSHA256,sha_(paths.ATModel)));
suite=legacy_(previousRun);
suite=extend_(suite,cfg);
protocol=struct('CreatedAt',char(datetime('now','TimeZone','UTC')), ...
    'PreviousRun',previousRun,'PreparedRun',preparedRun,'Config',cfg, ...
    'Spec',spec,'InputCount',numel(suite),'NormalModelSHA256',sha_(normalSource), ...
    'FaultModelSHA256',sha_(faultSource),'MATLAB',version, ...
    'Scope','Calibration only. Not a final evaluation set or an algorithm comparison.');
[status,commit]=system(sprintf('git -C "%s" rev-parse HEAD',paths.Repo));
assert(status==0); protocol.BaseCommit=strtrim(commit);
writeJson_(fullfile(runDirectory,'protocol.json'),protocol);
save(fullfile(runDirectory,'protocol.mat'),'protocol','spec','cfg','suite');
writeJson_(fullfile(runDirectory,'inputs.json'),suite);
addpath(folder,paths.ModelData,fullfile(paths.Repo,'s-taliro','dp_taliro'));
load_system(fullfile(runDirectory,'FInjLib.slx')); set_param('FInjLib','Lock','off');
load_system(fullfile(folder,'fim_rpmcal_normal.mdl'));
load_system(fullfile(folder,'fim_rpmcal_fault.slx'));
fault='fim_rpmcal_fault/Offset1';
assert(strcmp(get_param(fault,'LinkStatus'),'none'));
assert(strcmp(get_param([fault '/Step'],'Time'),'5'));
assert(strcmp(get_param('fim_rpmcal_normal','Solver'),'ode5'));
assert(str2double(get_param('fim_rpmcal_normal','FixedStep'))==0.01);
ph=get_param(fault,'PortHandles');
for pair={ph.Inport(1),'rpm_before';ph.Outport(1),'rpm_after'}'
    line=get_param(pair{1},'Line'); source=get_param(line,'SrcPortHandle');
    set_param(source,'DataLogging','on','DataLoggingNameMode','Custom', ...
        'DataLoggingName',pair{2});
end
save_system('fim_rpmcal_fault');
thresholds=struct([]);
for k=1:numel(suite)
    trace=simulate_('fim_rpmcal_normal',suite(k).U,spec,[],true);
    assert(trace.Rho>spec.Tolerance,'Normal model violated or touched the boundary.');
    legacyError=NaN;
    if strcmp(suite(k).Group,'legacy12')
        old=load(fullfile(previousRun,'exp1',['B00_' suite(k).ID '.mat']),'trace');
        assert(isequal(old.trace.T,trace.T));
        legacyError=max(abs(old.trace.Y-trace.Y),[],'all');
        assert(legacyError<1e-7);
    end
    active=trace.T>=spec.FaultTime-1e-10;
    indices=find(active); [peak,idx]=max(trace.Y(active,1));
    row=struct('Input',suite(k).ID,'Group',suite(k).Group,'Description',suite(k).Description, ...
        'MaximumRPM',peak,'PeakTime',trace.T(indices(idx)), ...
        'CriticalOffsetRPM',6001-peak,'BaselineRho',trace.Rho,'LegacyMaxError',legacyError);
    if isempty(thresholds), thresholds=row; else, thresholds(end+1)=row; end %#ok<AGROW>
    input=suite(k); %#ok<NASGU>
    save(fullfile(baselineFolder,[input.ID '.mat']),'trace','input');
    if mod(k,10)==0 || k==numel(suite)
        fprintf('RPM BASELINE %d/%d\n',k,numel(suite));
    end
end
thresholdTable=struct2table(thresholds);
writetable(thresholdTable,fullfile(runDirectory,'thresholds.csv'));
critical=thresholdTable.CriticalOffsetRPM;
minimum=min(critical);
recommendation=max(cfg.offset_min,ceil((minimum+cfg.recommendation_clearance_rpm)/ ...
    cfg.recommendation_step_rpm)*cfg.recommendation_step_rpm);
assert(recommendation<=cfg.offset_max, ...
    'No witness-preserving recommendation in the requested interval; expand only with user approval.');
isLegacy=strcmp(thresholdTable.Group,'legacy12');
offsets=unique([cfg.offset_min:cfg.fine_step:cfg.offset_max recommendation])';
curve=table(offsets,sum(offsets'>critical(isLegacy)+3000*spec.Tolerance,1)', ...
    sum(offsets'>critical(~isLegacy)+3000*spec.Tolerance,1)', ...
    'VariableNames',{'OffsetRPM','LegacyViolations','AdditionalViolations'});
curve.TotalViolations=curve.LegacyViolations+curve.AdditionalViolations;
writetable(curve,fullfile(runDirectory,'offset_curve.csv'));
% All fixed inputs at the recommendation; legacy12 also at both endpoints.
pairs=[(1:numel(suite))' repmat(recommendation,numel(suite),1)];
oldIndices=find(isLegacy);
pairs=[pairs;oldIndices repmat(cfg.offset_min,numel(oldIndices),1); ...
    oldIndices repmat(cfg.offset_max,numel(oldIndices),1)];
% Validate both sides AND exact equality of every legacy boundary in range,
% and the earliest newly observed boundary. All other curves are analytic.
boundaryIndices=find(isLegacy & critical>=cfg.offset_min & critical<=cfg.offset_max);
[~,first]=min(critical); boundaryIndices=unique([boundaryIndices;first]);
for index=boundaryIndices'
    for offset=[critical(index)-cfg.boundary_check_distance_rpm critical(index) ...
            critical(index)+cfg.boundary_check_distance_rpm]
        if offset>=cfg.offset_min && offset<=cfg.offset_max
            pairs(end+1,:)=[index offset]; %#ok<AGROW>
        end
    end
end
pairs=unique(pairs,'rows','stable');
checks=struct([]);
for j=1:size(pairs,1)
    k=pairs(j,1); offset=pairs(j,2);
    base=load(fullfile(baselineFolder,[suite(k).ID '.mat']),'trace');
    trace=simulate_('fim_rpmcal_fault',suite(k).U,spec,offset,true);
    expected=base.trace.Y;
    active=trace.T>=spec.FaultTime-1e-10;
    expected(active,1)=expected(active,1)+offset;
    err=max(abs(trace.Y-expected),[],'all');
    assert(isequal(trace.T,base.trace.T) && err<1e-7,'Offset changed plant dynamics or was not applied.');
    predicted=monitor_(expected,trace.T,spec);
    assert(abs(predicted-trace.Rho)<1e-9);
    assert(trace.InjectionMaxError<1e-7);
    row=struct('Input',suite(k).ID,'OffsetRPM',offset,'Rho',trace.Rho, ...
        'Violated',trace.Rho < -spec.Tolerance,'Boundary',abs(trace.Rho)<=spec.Tolerance, ...
        'ExpectedWaveformMaxError',err,'InjectionMaxError',trace.InjectionMaxError, ...
        'MonitorError',trace.MonitorError);
    if isempty(checks), checks=row; else, checks(end+1)=row; end %#ok<AGROW>
    input=suite(k); %#ok<NASGU>
    save(fullfile(validationFolder,sprintf('V%04d.mat',j)),'trace','input','offset');
    if mod(j,10)==0 || j==size(pairs,1), fprintf('RPM FIM CHECK %d/%d\n',j,size(pairs,1)); end
end
% Explicit OFF check on a witness input, independent of the additive prediction.
base=load(fullfile(baselineFolder,[suite(first).ID '.mat']),'trace');
off=simulate_('fim_rpmcal_fault',suite(first).U,spec,recommendation,false);
offError=max(abs(off.Y-base.trace.Y),[],'all'); assert(offError<1e-7);
input=suite(first); save(fullfile(runDirectory,'fault_off.mat'),'off','input','offError');
writetable(struct2table(checks),fullfile(runDirectory,'validation.csv'));
summary=struct('RecommendedOffsetRPM',recommendation,'MinimumCriticalOffsetRPM',minimum, ...
    'MinimumLegacyCriticalOffsetRPM',min(critical(isLegacy)), ...
    'AllLegacyCriticalOffsetRPM',max(critical(isLegacy)), ...
    'InputCount',numel(suite),'LegacyInputs',sum(isLegacy),'AdditionalInputs',sum(~isLegacy), ...
    'LegacyViolationsAtRecommendation',sum(recommendation>critical(isLegacy)+3000*spec.Tolerance), ...
    'AdditionalViolationsAtRecommendation',sum(recommendation>critical(~isLegacy)+3000*spec.Tolerance), ...
    'ActualFIMChecks',height(struct2table(checks)),'FaultOffMaxError',offError, ...
    'MaximumWaveformError',max([checks.ExpectedWaveformMaxError]), ...
    'MaximumMonitorError',max([checks.MonitorError]),'Scope',cfg.scope);
writeJson_(fullfile(runDirectory,'summary.json'),summary);
disp(summary);
fprintf('CALIBRATION_RUN=%s\n',runDirectory);
end

function suite=legacy_(previousRun)
suite=struct([]);
for k=1:12
    id=sprintf('U%02d',k); file=fullfile(previousRun,'exp1',['B00_' id '.mat']);
    x=load(file,'trace');
    row=struct('ID',id,'Group','legacy12','Description',['Historical fixed input ' id], ...
        'U',x.trace.U,'SourceSHA256',sha_(file));
    if isempty(suite), suite=row; else, suite(end+1)=row; end %#ok<AGROW>
end
end

function suite=extend_(suite,cfg)
t=(0:5:30)';
for throttle=cfg.constant_throttle(:)'
    for brake=cfg.constant_brake(:)'
        suite=append_(suite,[t repmat([throttle brake],7,1)], ...
            sprintf('constant throttle=%g brake=%g',throttle,brake));
    end
end
for low=cfg.step_throttle_initial(:)'
    for high=cfg.step_throttle_final(:)'
        for when=cfg.step_times(:)'
            a=repmat(low,7,1); a(t>=when)=high;
            suite=append_(suite,[t a zeros(7,1)], ...
                sprintf('throttle %g->%g at %gs; brake=0',low,high,when));
        end
    end
end
for low=cfg.brake_step_levels(:)'
    for high=cfg.brake_step_levels(:)'
        if low==high, continue; end
        for when=cfg.step_times(:)'
            b=repmat(low,7,1); b(t>=when)=high;
            suite=append_(suite,[t repmat(100,7,1) b], ...
                sprintf('throttle=100; brake %g->%g at %gs',low,high,when));
        end
    end
end
end

function suite=append_(suite,u,description)
for k=1:numel(suite), if isequal(suite(k).U,u), return; end, end
suite(end+1)=struct('ID',sprintf('D%03d',numel(suite)-11),'Group','additional_fixed', ...
    'Description',description,'U',u,'SourceSHA256','generated from declared config');
end

function trace=simulate_(model,u,spec,offset,enabled)
assert(isequal(u(:,1),(0:5:30)') && all(isfinite(u),'all'));
assert(all(u(:,2:3)>=spec.InputRange(:,1)','all') && all(u(:,2:3)<=spec.InputRange(:,2)','all'));
in=Simulink.SimulationInput(model);
in=in.setVariable('u',u);
in=in.setModelParameter('SimulationMode','normal','StopTime','30', ...
    'LoadExternalInput','on','ExternalInput','u','SaveTime','on','TimeSaveName','tout', ...
    'SaveOutput','on','OutputSaveName','yout','SaveFormat','Array', ...
    'SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
if ~isempty(offset)
    block=[model '/Offset1'];
    in=in.setBlockParameter(block,'FaultValue',num2str(offset,17));
    in=in.setBlockParameter([block '/Fault value'],'Value',num2str(offset,17));
    in=in.setBlockParameter([block '/Enable_flag'],'Value',num2str(enabled));
end
out=sim(in); trace=struct('T',out.tout,'Y',out.yout(:,[2 1 3]),'U',u);
assert(numel(trace.T)==3001 && max(abs(trace.T-(0:.01:30)'))<1e-10);
assert(all(isfinite(trace.Y),'all'));
[trace.Rho,trace.MonitorError]=monitor_(trace.Y,trace.T,spec);
if ~isempty(offset)
    b=out.logsout.get('rpm_before').Values; a=out.logsout.get('rpm_after').Values;
    assert(isequal(b.Time,a.Time));
    expected=double(b.Data)+offset*(enabled & a.Time>=spec.FaultTime-1e-10);
    trace.InjectionMaxError=max(abs(double(a.Data)-expected),[],'all');
    trace.Injected=struct('T',a.Time,'Before',b.Data,'After',a.Data);
end
end

function [rho,error]=monitor_(y,t,spec)
z=[(y(:,1)-599)/3000 (6001-y(:,1))/3000 (y(:,3)-.5)/1.5 (4.5-y(:,3))/1.5];
rho=min(z,[],'all');
names={'rpmlo','rpmhi','gearlo','gearhi'};
for k=1:4, p(k).str=names{k}; p(k).A=zeros(1,4); p(k).A(k)=-1; p(k).b=0; end %#ok<AGROW>
independent=dp_taliro(spec.Formula,p,z,t,[],[],[]);
error=abs(rho-independent); assert(error<1e-9);
end

function value=sha_(file)
fid=fopen(file,'rb'); assert(fid>=0); clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid), md.update(fread(fid,1024*1024,'*uint8')); end
value=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2)',1,[]));
end

function writeJson_(file,value)
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function restore_(before,oldPath,oldDir,oldWarnings)
now=find_system('type','block_diagram');
for k=1:numel(now)
    if ~ismember(now{k},before), try, close_system(now{k},0); catch, end, end
end
path(oldPath); cd(oldDir); warning(oldWarnings);
end

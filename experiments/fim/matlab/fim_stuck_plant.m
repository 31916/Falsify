function trace=fim_stuck_plant(campaign,caseID,u,outputFile,faultEnabled)
% Native Stuck-at plant replay. Also audit the internal held gear and lookup.
if nargin<4, outputFile=''; end
if nargin<5, faultEnabled=true; end
assert(isequal(size(u),[7 3]) && all(isfinite(u),'all'));
assert(isequal(u(:,1),(0:5:30)') && all(u(:,2)>=60 & u(:,2)<=100) && all(u(:,3)==0));
assert(isequal(u(end,2:3),u(end-1,2:3)),'No extra terminal control point.');
paths=fim_paths(); spec=fim_torque_spec();
catalog=readtable(fullfile(campaign,'fault_catalog.csv'),'TextType','string');
c=catalog(catalog.ID==string(caseID),:); assert(height(c)==1,'Unknown Stuck-at case.');
addpath(fullfile(campaign,'plants'),paths.ModelData,fullfile(paths.Repo,'s-taliro','dp_taliro'));
if ~bdIsLoaded('FInjLib'), load_system(fullfile(campaign,'FInjLib.slx')); set_param('FInjLib','Lock','off'); end
model=char(c.Model); load_system(model); faulty=c.ID~="B00";
in=Simulink.SimulationInput(model); in=in.setVariable('u',u);
if faulty
    flag='off'; if faultEnabled, flag='on'; end
    in=in.setBlockParameter([model '/' char(c.FaultBlock)],'FIEnableflag',flag);
end
in=in.setModelParameter('SimulationMode','normal','StopTime','30','LoadExternalInput','on', ...
    'ExternalInput','u','SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout', ...
    'SaveFormat','Array','SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
started=tic; out=sim(in); elapsed=toc(started);
t=out.tout; y=out.yout(:,[2 1 3]);
assert(numel(t)==3001 && max(abs(t-(0:.01:30)'))<1e-10);
target=struct('DeadlineSeconds',20,'TargetSpeedMPH',95,'Formula','<>_[0,20](fast)');
monitor=fim_torque_monitor(t,y,target,spec); assert(monitor.GearPass);
[command,raw.Command]=logged_(out,'gear_command',t); applied=command; gate=zeros(size(t));
if faulty
    [applied,raw.Applied]=logged_(out,'gear_applied',t);
    [gate,raw.Gate]=logged_(out,'fault_gate',t);
    active=t>=c.Onset-1e-10 & t<c.Onset+c.Duration-1e-10;
    % Gate is the native timing pulse; FIEnableflag bypasses its effect.
    assert(isequal(gate,double(active)),'Native FIM gate duration mismatch.');
    expected=command;
    if faultEnabled, expected(active)=command(find(t<c.Onset-1e-10,1,'last')); end
    assert(isequal(applied,expected),'Native FIM hold/release mismatch.');
end
assert(all(ismember(command,[1 2 3 4])) && all(ismember(applied,[1 2 3 4])));
[ratio,raw.Ratio]=logged_(out,'gear_ratio',t); ratios=[2.393 1.450 1.000 .677];
assert(max(abs(ratio-reshape(ratios(applied),[],1)))<1e-10);
trace=struct('T',t,'Y',y,'U',u,'Case',caseID,'Command',command,'Applied',applied, ...
    'Ratio',ratio,'Gate',gate,'Monitor',monitor,'Rho',monitor.AccelerationRhoMPH/80, ...
    'SimulationSeconds',elapsed,'HeldSamples',sum(command~=applied),'RawSignals',raw);
if ~isempty(outputFile), save(outputFile,'trace'); end
end

function [values,raw]=logged_(out,name,t)
x=out.logsout.get(name).Values;
raw=struct('Time',double(x.Time(:)),'Values',double(x.Data(:)));
assert(all(isfinite(raw.Values)) && all(diff(raw.Time)>0));
assert(raw.Time(1)==0 && abs(raw.Time(end)-30)<1e-10);
% The gear command/lookup has a native 0.04 s sample time. Preserve raw logs
% and align discrete timestamps by zero-order hold, never round gear values.
ticks=round(raw.Time/.01); assert(max(abs(raw.Time-ticks*.01))<1e-9);
values=interp1(ticks,raw.Values,round(t/.01),'previous');
assert(all(isfinite(values)));
end

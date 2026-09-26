function run_fim_stuck_pilot(campaign)
% Fixed paired screen. A held command can affect dynamics without violating STL.
paths=fim_paths(); spec=fim_torque_spec();
addpath(fullfile(campaign,'plants'),paths.ModelData,fullfile(paths.Repo,'s-taliro','dp_taliro'));
load_system(fullfile(campaign,'FInjLib.slx')); set_param('FInjLib','Lock','off');
cases=readtable(fullfile(campaign,'fault_catalog.csv'),'TextType','string');
inputs=readtable(fullfile(campaign,'fixed-inputs.csv'),'TextType','string');
folder=fullfile(campaign,'fixed'); mkdir(folder); mkdir(fullfile(folder,'traces'));
rows={}; checks={};
for k=1:height(inputs)
    throttle=inputs{k,3:8}'; u=[(0:5:30)' [throttle;throttle(end)] zeros(7,1)];
    normal=[];
    for j=1:height(cases)
        tr=plant_(cases(j,:),u,true,spec);
        if j==1, normal=tr; assert(tr.Margin>=0,'Normal input violates frozen acceleration requirement.'); end
        pre=true(size(tr.T)); if j>1, pre=tr.T<cases.Onset(j)-1e-10; end
        error_=max(abs(tr.Y(pre,:)-normal.Y(pre,:)),[],'all'); assert(error_<1e-7);
        id=char(cases.ID(j)); input=char(inputs.InputID(k));
        save(fullfile(folder,'traces',[id '_' input '.mat']),'tr');
        values=[tr.T tr.Y tr.Command tr.Applied tr.Ratio tr.Gate];
        writetable(array2table(values,'VariableNames',{'TimeSeconds','RPM','SpeedMPH','Gear', ...
            'CommandedGear','AppliedGear','GearRatio','FaultGate'}),fullfile(folder,'traces',[id '_' input '.csv']));
        row=struct('Case',id,'InputID',input,'Source',char(inputs.Source(k)), ...
            'Onset',cases.Onset(j),'Duration',cases.Duration(j),'MarginMPH',tr.Margin, ...
            'NormalMarginMPH',normal.Margin,'Violation',tr.Margin<0,'GearPass',true, ...
            'HeldSamples',sum(tr.Command~=tr.Applied),'FirstReachSeconds',tr.FirstReach, ...
            'BeforeFaultError',error_,'SimulationSeconds',tr.Seconds);
        rows{end+1}=row; %#ok<AGROW>
        if j>1 && (k<=6 || tr.Margin<0)
            off=plant_(cases(j,:),u,false,spec);
            offError=max(abs(off.Y-normal.Y),[],'all'); assert(offError<1e-7);
            replay=NaN;
            if tr.Margin<0
                repeat=plant_(cases(j,:),u,true,spec);
                replay=max(abs(repeat.Y-tr.Y),[],'all'); assert(replay<1e-7);
            end
            checks{end+1}=struct('Case',id,'InputID',input,'DisabledReplayError',offError, ...
                'CounterexampleReplayError',replay); %#ok<AGROW>
        end
    end
    if mod(k,10)==0 || k==height(inputs)
        writetable(struct2table([rows{:}]),fullfile(folder,'results.csv'));
        fprintf('STUCK FIXED %d/%d inputs completed\n',k,height(inputs));
    end
end
writetable(struct2table([checks{:}]),fullfile(folder,'checks.csv'));
fid=fopen(fullfile(folder,'complete.json'),'w'); assert(fid>=0);
fprintf(fid,'%s\n',jsonencode(struct('Status','PASS','Comparisons',numel(rows),'Checks',numel(checks)))); fclose(fid);
end

function tr=plant_(c,u,enabled,spec)
model=char(c.Model); load_system(model); faulty=c.ID~="B00";
in=Simulink.SimulationInput(model); in=in.setVariable('u',u);
if faulty
    flag='off'; if enabled, flag='on'; end
    in=in.setBlockParameter([model '/' char(c.FaultBlock)],'FIEnableflag',flag);
end
in=in.setModelParameter('SimulationMode','normal','StopTime','30','LoadExternalInput','on', ...
    'ExternalInput','u','SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout', ...
    'SaveFormat','Array','SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
started=tic; out=sim(in); seconds=toc(started);
t=out.tout; y=out.yout(:,[2 1 3]);
assert(numel(t)==3001 && max(abs(t-(0:.01:30)'))<1e-10);
target=struct('DeadlineSeconds',20,'TargetSpeedMPH',95,'Formula','<>_[0,20](fast)');
m=fim_torque_monitor(t,y,target,spec); assert(m.GearPass);
[command,raw.Command]=logged_(out,'gear_command',t); applied=command; gate=zeros(size(t));
if faulty
    [applied,raw.Applied]=logged_(out,'gear_applied',t); [gate,raw.Gate]=logged_(out,'fault_gate',t);
    active=t>=c.Onset-1e-10 & t<c.Onset+c.Duration-1e-10;
    assert(isequal(gate,double(active)),'Native FIM gate duration mismatch.');
    expected=command;
    if enabled, expected(active)=command(find(t<c.Onset-1e-10,1,'last')); end
    assert(isequal(applied,expected),'Native FIM hold/release mismatch.');
end
assert(all(ismember(command,[1 2 3 4])) && all(ismember(applied,[1 2 3 4])));
[ratio,raw.Ratio]=logged_(out,'gear_ratio',t); ratios=[2.393 1.450 1.000 .677];
assert(max(abs(ratio-reshape(ratios(applied),[],1)))<1e-10);
tr=struct('T',t,'Y',y,'Command',command,'Applied',applied,'Ratio',ratio,'Gate',gate, ...
    'Margin',m.AccelerationRhoMPH,'FirstReach',m.FirstReachSeconds,'Seconds',seconds,'RawSignals',raw);
end

function [values,raw]=logged_(out,name,t)
x=out.logsout.get(name).Values;
raw=struct('Time',double(x.Time(:)),'Values',double(x.Data(:)));
assert(all(isfinite(raw.Values)) && all(diff(raw.Time)>0));
assert(raw.Time(1)==0 && abs(raw.Time(end)-30)<1e-10);
% AT gear is natively sampled at 0.04 s. Keep raw timestamps in MAT and align
% discrete logs by zero-order hold; never interpolate/round gear VALUES.
ticks=round(raw.Time/.01); assert(max(abs(raw.Time-ticks*.01))<1e-9);
values=interp1(ticks,raw.Values,round(t/.01),'previous');
assert(all(isfinite(values)));
end

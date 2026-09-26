function trace=fim_comparison_plant(campaign,caseID,u,outputFile,faultEnabled)
% One candidate simulation on the copied FIM plant. No normal simulation here.
if nargin<4, outputFile=''; end
if nargin<5, faultEnabled=true; end
paths=fim_paths(); spec=fim_torque_spec();
target=struct('DeadlineSeconds',20,'TargetSpeedMPH',95,'Formula','<>_[0,20](fast)');
catalogFile=fullfile(campaign,'fault_catalog.csv');
assert(isfile(catalogFile),'Each campaign requires its own generated fault catalog.');
delta=0; faultBlock='';
    catalog=readtable(catalogFile,'TextType','string');
    index=find(catalog.ID==string(caseID)); assert(isscalar(index),'Unknown fault case.');
    delta=catalog.Delta(index);
    if ~strcmp(caseID,'B00')
        assert(~ismissing(catalog.FaultBlock(index)),'Fault block is missing.');
        faultBlock=char(catalog.FaultBlock(index));
    end
assert(isfinite(delta) && delta>=0 && delta<1);
assert(isequal(size(u),[7 3]) && all(isfinite(u),'all'));
assert(isequal(u(:,1),(0:5:30)') && all(u(:,2)>=60 & u(:,2)<=100) && all(u(:,3)==0));
assert(isequal(u(end,2:3),u(end-1,2:3)),'No extra terminal control point.');
addpath(fullfile(campaign,'plants'),paths.ModelData,fullfile(paths.Repo,'s-taliro','dp_taliro'));
if ~bdIsLoaded('FInjLib'), load_system(fullfile(campaign,'FInjLib.slx')); set_param('FInjLib','Lock','off'); end
model=['fim_tq_' caseID]; load_system(model);
in=Simulink.SimulationInput(model); in=in.setVariable('u',u);
if ~strcmp(caseID,'B00')
    in=in.setBlockParameter([model '/' faultBlock '/Enable_flag'],'Value',num2str(logical(faultEnabled)));
end
in=in.setModelParameter('SimulationMode','normal','StopTime','30','LoadExternalInput','on', ...
    'ExternalInput','u','SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout', ...
    'SaveFormat','Array','SignalLogging','on','SignalLoggingName','logsout','ReturnWorkspaceOutputs','on');
started=tic; out=sim(in); elapsed=toc(started);
trace=struct('T',out.tout,'Y',out.yout(:,[2 1 3]),'U',u,'SimulationSeconds',elapsed,'Case',caseID);
assert(numel(trace.T)==3001 && max(abs(trace.T-(0:.01:30)'))<1e-10);
trace.Monitor=fim_torque_monitor(trace.T,trace.Y,target,spec);
assert(trace.Monitor.GearPass,'FIM:GearIntegrity','Unexpected gear violation; stop for protocol review.');
before=out.logsout.get('ratio_before').Values;
trace.RatioBefore=double(before.Data(:)); trace.RatioAfter=trace.RatioBefore;
assert(isequal(before.Time,trace.T));
if ~strcmp(caseID,'B00')
    after=out.logsout.get('ratio_after').Values; assert(isequal(after.Time,trace.T));
    trace.RatioAfter=double(after.Data(:));
end
active=trace.T>=5-1e-10 & logical(faultEnabled);
trace.InjectionError=max(abs(trace.RatioAfter-(trace.RatioBefore-delta*active)));
assert(trace.InjectionError<1e-10 && all(trace.RatioAfter>0));
impeller=out.logsout.get('impeller_torque').Values;
turbine=out.logsout.get('turbine_torque').Values;
assert(isequal(impeller.Time,trace.T) && isequal(turbine.Time,trace.T));
trace.ImpellerTorque=double(impeller.Data(:)); trace.TurbineTorque=double(turbine.Data(:));
trace.TorqueProductError=max(abs(trace.TurbineTorque-trace.ImpellerTorque.*trace.RatioAfter));
assert(trace.TorqueProductError<1e-7);
trace.Rho=trace.Monitor.AccelerationRhoMPH/80;
if ~isempty(outputFile), save(outputFile,'trace'); end
end

function test_fim_stuck_native(campaign)
% Test the actual FIM hold circuit with a command change inside every window.
load_system(fullfile(campaign,'FInjLib.slx')); set_param('FInjLib','Lock','off');
model='fim_stuck_unit'; new_system(model);
cleanup=onCleanup(@()close_system(model,0)); %#ok<NASGU>
add_block('simulink/Sources/From Workspace',[model '/Input'],'VariableName','u','Interpolate','off', ...
    'SampleTime','0.01','OutputAfterFinalValue','Holding final value');
add_block('FInjLib/Stuck-at',[model '/Fault']); set_param([model '/Fault'],'LinkStatus','none');
add_block('simulink/Sinks/Out1',[model '/Output']);
add_line(model,'Input/1','Fault/1'); add_line(model,'Fault/1','Output/1');
set_param(model,'Solver','ode5','FixedStep','.01','StopTime','30','SaveFormat','Array', ...
    'SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout');
rows={};
for onset=[5 10 15]
 for duration=[.2 .5 1]
  for enabled=[true false]
    t=(0:.01:30)'; command=2*ones(size(t)); command(t>=onset+duration/2-1e-10)=3;
    u=[t command]; active=t>=onset-1e-10 & t<onset+duration-1e-10;
    expected=command; if enabled, expected(active)=2; end
    flag='off'; if enabled, flag='on'; end
    set_param([model '/Fault'],'FaultOccurenceTime',num2str(onset), ...
        'FaultDuration',num2str(duration),'FaultEffect','Constant time','FIEnableflag',flag);
    fim_configure_stuck([model '/Fault']);
    in=Simulink.SimulationInput(model); in=in.setVariable('u',u);
    out=sim(in); assert(isequal(out.tout,t) || max(abs(out.tout-t))<1e-10);
    error_=max(abs(out.yout-expected)); assert(error_==0,'Stuck hold test failed.');
    rows{end+1}=struct('Onset',onset,'Duration',duration,'Enabled',enabled,'MaximumError',error_); %#ok<AGROW>
  end
 end
end
writetable(struct2table([rows{:}]),fullfile(campaign,'native-block-checks.csv'));
fprintf('PASS: 18 native Stuck-at hold/release/disable tests.\n');
end

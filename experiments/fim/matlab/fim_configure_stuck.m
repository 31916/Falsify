function fim_configure_stuck(block)
% Instance-local initialization for the native FIM hold circuit.
% Native mask writes FInjLib rather than its instance. Set an explicit 0.01 s
% sample-based gate; width/delay/period use sample counts, not seconds.
enabled=strcmp(get_param(block,'FIEnableflag'),'on');
onset=str2double(get_param(block,'FaultOccurenceTime'));
assert(isfinite(onset) && onset>0);
set_param([block '/Enable_flag'],'Value',num2str(enabled));
if strcmp(get_param(block,'FaultEffect'),'Infinite time')
    set_param([block '/Faulttype'],'Value','1');
    set_param([block '/Step'],'Time',num2str(onset,17));
else
    duration=str2double(get_param(block,'FaultDuration'));
    assert(isfinite(duration) && duration>0 && onset+duration<30);
    pulse=find_system(block,'SearchDepth',1,'LookUnderMasks','all','BlockType','DiscretePulseGenerator');
    assert(numel(pulse)==1);
    set_param([block '/Faulttype'],'Value','2');
    % One pulse in 30 s. Explicit mode/units avoid inherited library defaults.
    assert(abs(duration/.01-round(duration/.01))<1e-8);
    set_param(pulse{1},'PulseType','Sample based','SampleTime','.01', ...
        'Period','50000','PhaseDelay',num2str(round(onset/.01)), ...
        'PulseWidth',num2str(round(duration/.01)));
end
end

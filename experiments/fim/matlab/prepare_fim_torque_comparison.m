function prepare_fim_torque_comparison(campaign)
% Build only derived wrappers. Static plants were copied by the coordinator.
paths=fim_paths(); addpath(fullfile(campaign,'plants'),paths.ModelData);
outdir=fullfile(campaign,'wrappers'); if ~isfolder(outdir), mkdir(outdir); end
load_system(fullfile(campaign,'FInjLib.slx')); set_param('FInjLib','Lock','off');
load_system(fullfile(paths.Repo,'autotrans','autotrans_mod04.slx'));
protocol=jsondecode(fileread(fullfile(campaign,'protocol.json')));
catalog=readtable(fullfile(campaign,'fault_catalog.csv'),'TextType','string');
for id=[{'B00'} reshape(cellstr(string(protocol.cases)),1,[])]
    index=find(catalog.ID==string(id{1})); assert(isscalar(index));
    source=char(catalog.Model(index)); model=['fim_cmp_' id{1}];
    file=fullfile(campaign,'plants',[source '.slx']);
    if ~isfile(file), file=fullfile(campaign,'plants',[source '.mdl']); end
    load_system(file); save_system(source,fullfile(outdir,[model '.slx']));
    inputs=find_system(model,'SearchDepth',1,'BlockType','Inport'); destinations=cell(1,2);
    for k=1:numel(inputs)
        number=str2double(get_param(inputs{k},'Port')); p=get_param(inputs{k},'PortHandles');
        line=get_param(p.Outport,'Line'); handles=get_param(line,'DstPortHandle');
        destinations{number}=arrayfun(@(h) portname(model,h),handles,'UniformOutput',false);
    end
    for k=1:numel(inputs)
        p=get_param(inputs{k},'PortHandles'); delete_line(get_param(p.Outport,'Line')); delete_block(inputs{k});
    end
    outputs=find_system(model,'SearchDepth',1,'BlockType','Outport'); sources=cell(1,3);
    for k=1:numel(outputs)
        number=str2double(get_param(outputs{k},'Port')); p=get_param(outputs{k},'PortHandles');
        line=get_param(p.Inport,'Line'); source=get_param(line,'SrcPortHandle');
        sources{number}=portname(model,source);
    end
    for k=1:numel(outputs)
        p=get_param(outputs{k},'PortHandles'); line=get_param(p.Inport,'Line');
        delete_line(model,get_param(line,'SrcPortHandle'),p.Inport); delete_block(outputs{k});
    end
    assert(all(~cellfun(@isempty,sources)) && all(~cellfun(@isempty,destinations)));
    add_block('autotrans_mod04/RL agent',[model '/RL agent']);
    set_param([model '/RL agent'],'System','fim_comparison_agent', ...
        'sample_time','5','input_range','[60 100]','stop_time','30');
    add_block('simulink/Sources/Constant',[model '/Zero brake'],'Value','0');
    add_block('simulink/Sources/Constant',[model '/Zero intermediate reward'],'Value','0');
    add_block('simulink/Signal Routing/Mux',[model '/Actual state'],'Inputs','3');
    add_block('simulink/Signal Routing/Mux',[model '/Observed state'],'Inputs','3');
    add_block('simulink/Discrete/Memory',[model '/Gear observation memory'],'InitialCondition','1');
    for name={'Actual','Observed'}
        add_block('simulink/Math Operations/Bias',[model '/' name{1} ' center'],'Bias','[-3000;-80;-2.5]');
        add_block('simulink/Math Operations/Gain',[model '/' name{1} ' normalize'], ...
            'Gain','[1/3000;1/80;1/1.5]','Multiplication','Element-wise(K.*u)');
        add_line(model,[name{1} ' state/1'],[name{1} ' center/1']);
        add_line(model,[name{1} ' center/1'],[name{1} ' normalize/1']);
    end
    order=[2 1 3];
    for k=1:3, add_line(model,sources{order(k)},sprintf('Actual state/%d',k)); end
    for k=1:2, add_line(model,sources{order(k)},sprintf('Observed state/%d',k)); end
    add_line(model,sources{3},'Gear observation memory/1');
    add_line(model,'Gear observation memory/1','Observed state/3');
    add_line(model,'Observed normalize/1','RL agent/1');
    for h=reshape(destinations{1},1,[]), add_line(model,'RL agent/1',h{1}); end
    for h=reshape(destinations{2},1,[]), add_line(model,'Zero brake/1',h{1}); end
    for k=1:3
        names={'RewardOut','StateOut','ActionOut'};
        add_block('simulink/Sinks/Out1',[model '/' names{k}],'Port',num2str(k));
    end
    add_line(model,'Zero intermediate reward/1','RewardOut/1');
    add_line(model,'Actual normalize/1','StateOut/1');
    add_line(model,'RL agent/1','ActionOut/1');
    set_param(model,'LoadExternalInput','off','SimulationMode','normal','StopTime','30', ...
        'SaveFormat','Dataset','SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout');
    assert(strcmp(get_param(model,'Solver'),'ode5') && str2double(get_param(model,'FixedStep'))==.01);
    save_system(model); close_system(model,0);
end

function name=portname(model,handle)
parent=get_param(handle,'Parent');
name=sprintf('%s/%d',parent(numel(model)+2:end),get_param(handle,'PortNumber'));
end
close_system('autotrans_mod04',0); close_system('FInjLib',0);
fprintf('Prepared FIM comparison wrappers.\n');
end

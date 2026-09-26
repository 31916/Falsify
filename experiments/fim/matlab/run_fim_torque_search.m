function result=run_fim_torque_search(campaign,caseID,algorithm,seed,budget,folder)
% Actual Falsify loop, with a FIM-only bridge and an audited episode objective.
paths=fim_paths(); assert(~isfolder(folder),'Use a fresh trial directory.'); mkdir(folder);
cleanup=onCleanup(@() cd(paths.Repo)); cd(paths.Repo);
pyenv('Version',fullfile(paths.Repo,'.venv-falsify','bin','python'));
insert(py.sys.path,int32(0),paths.Repo);
insert(py.sys.path,int32(0),fullfile(paths.Experiment,'python'));
py.importlib.import_module('fim_comparison_driver'); py.fim_comparison_driver.install(int32(10000));
rng(seed,'twister'); py.numpy.random.seed(int32(seed)); py.random.seed(int32(seed));
addpath(fullfile(campaign,'wrappers'),fullfile(campaign,'plants'), ...
    fullfile(paths.Repo,'s-taliro','dp_taliro'));
load_system(fullfile(campaign,'FInjLib.slx')); set_param('FInjLib','Lock','off');
config=struct('option',algorithm,'maxEpisodes',budget,'input_range',[60 100], ...
    'output_range',[0 6000;0 160;1 4],'sampleTime',5,'stopTime',30, ...
    'mdl',['fim_cmp_' caseID],'agentName','/RL agent','alpha',0, ...
    'useModelSolverSettings',true,'targetFormula','<>_[0,20](fast)', ...
    'monitoringFormula','<>_[0,20](fast)','objectiveSource','FIM acceleration /80');
config.preds=struct('str','fast','A',[0 -1 0],'b',-95);
config.episodeEvaluator=@evaluate;
target=struct('DeadlineSeconds',20,'TargetSpeedMPH',95,'Formula','<>_[0,20](fast)');
spec=fim_torque_spec(); verificationSeconds=0; verificationSimulations=0;
episode=0; best=inf; history={}; started=tic;
[count,~,rho,~,~,~,~]=falsify(config);
searchSeconds=toc(started)-verificationSeconds;
stats=jsondecode(char(py.fim_comparison_driver.stats_json()));
assert(stats.CompletedEpisodes==count && stats.Transitions==6*count);
result=struct('Case',caseID,'Algorithm',algorithm,'Seed',seed,'Episodes',count, ...
    'Budget',budget,'Violated',rho<0,'Rho',rho,'RhoMPH',rho*80, ...
    'SearchSeconds',searchSeconds,'VerificationSeconds',verificationSeconds, ...
    'VerificationSimulations',verificationSimulations,'Learning',stats,'Status','complete');
writejson(fullfile(folder,'result.json'),result);
save(fullfile(folder,'history.mat'),'history','result');
fprintf('COMPLETE %s %s %d: %d inputs, rho=%g, updates=%d\n', ...
    caseID,algorithm,seed,count,rho,stats.OptimizerUpdates);

    function [rob,evaluation]=evaluate(yout)
        episode=episode+1;
        state=yout.getElement(2).Values;
        T=double(state.Time(:)); Y=double(squeeze(state.Data));
        if size(Y,1)~=numel(T), Y=Y'; end
        Y=Y.*[3000 80 1.5]+[3000 80 2.5];
        assert(numel(T)==3001 && max(abs(T-(0:.01:30)'))<1e-10);
        av=yout.getElement(3).Values; at=double(av.Time(:)); ad=double(av.Data(:));
        throttle=zeros(7,1);
        for j=1:7
            ix=find(abs(at-(j-1)*5)<1e-8,1,'last'); assert(~isempty(ix));
            throttle(j)=ad(ix);
        end
        assert(throttle(end)==throttle(end-1));
        U=[(0:5:30)' throttle zeros(7,1)];
        actions=jsondecode(char(py.fim_comparison_driver.episode_json()));
        assert(numel(actions)==6 && max(abs([actions.Time]-(0:5:25)))<1e-10);
        assert(max(abs(throttle(1:6)'-(80+20*[actions.Action])))<1e-8, ...
            'FIM:ActionTiming','Recorded agent actions differ from applied plant inputs.');
        monitor=fim_torque_monitor(T,Y,target,spec);
        assert(monitor.GearPass,'FIM:GearIntegrity','Unexpected gear anomaly.');
        rob=monitor.AccelerationRhoMPH/80;
        evaluation=struct('Episode',episode,'Rho',rob,'RhoMPH',rob*80, ...
            'Throttle',throttle(1:6)','GearPass',monitor.GearPass, ...
            'Verification',struct(),'LearningBeforeTerminalUpdate', ...
            jsondecode(char(py.fim_comparison_driver.stats_json())));
        if episode==1 || rob<0
            verification=fim_comparison_verify(campaign,caseID,U,Y, ...
                fullfile(folder,sprintf('verification_%04d',episode)));
            verificationSeconds=verificationSeconds+verification.Seconds;
            verificationSimulations=verificationSimulations+verification.Simulations;
            assert(rob>=0 || verification.ValidCounterexample);
            evaluation.Verification=verification;
        end
        evaluation.SearchSeconds=toc(started)-verificationSeconds;
        history{episode}=evaluation;
        fid=fopen(fullfile(folder,'candidates.jsonl'),'a'); assert(fid>=0);
        fprintf(fid,'%s\n',jsonencode(evaluation)); fclose(fid);
        if rob<best
            best=rob;
            save(fullfile(folder,'best.mat'),'T','Y','U','monitor','actions','evaluation');
            writetable(array2table([T Y],'VariableNames',{'TimeSeconds','RPM','SpeedMPH','Gear'}), ...
                fullfile(folder,'best-trace.csv'));
        end
    end
end

function writejson(file,value)
fid=fopen(file,'w'); assert(fid>=0); guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

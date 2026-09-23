function fim_at_external(runDirectory,caseID,u,outputFile)
%FIM_AT_EXTERNAL Engine entry point after setup_fim; reuse FIM replay.
options=struct('Case',caseID,'U',u,'File',outputFile);
run_fim_at_experiments('external',runDirectory,options);
end

function fim_at_external(runDirectory,caseID,u,outputFile)
%FIM_AT_EXTERNAL Engine entry point; reuse the exact FIM replay implementation.
options=struct('Case',caseID,'U',u,'File',outputFile);
run_fim_at_experiments('external',runDirectory,options);
end

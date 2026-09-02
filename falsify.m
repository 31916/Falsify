function [numEpisode, elapsedTime, bestRob, bestXout, bestYout] = falsify(config)

    function [Y, T, R] = yout2TY(yout)
            Y = double(squeeze(yout.getElement(2).Values.Data));
            T = double(yout.getElement(2).Values.Time(:));
            if isvector(Y)
                if numel(Y) == numel(T)
                    Y = Y(:);
                else
                    Y = reshape(Y, 1, []);
                end
            end
            if size(Y, 1) ~= numel(T) && size(Y, 2) == numel(T)
                Y = Y.';
            end
            assert(size(Y, 1) == numel(T), ...
                'falsify:InvalidLoggedStateShape', ...
                'StateOut data must have one row per logged time sample.');
            [T,ia,~] = unique(T,'first');
            Y = Y(ia,:);
            R = double(squeeze(yout.getElement(1).Values.Data));
            R = R(end);
    end

    function [normal_preds] = normalize_pred(preds, range)
       normal_preds = [];
       lower = range(:,1);
       upper = range(:,2);
       middle = (lower + upper)/2;
       d = (upper - lower)/2;
       dd = diag(d);
       for i = 1:size(preds,2)
          normal_preds(i).str = preds(i).str;
          normal_preds(i).A = preds(i).A * dd;
          normal_preds(i).b = preds(i).b - preds(i).A * middle;
       end
    end

    function [tout, xout, yout] = runsim(config, normal_preds)
        %mws = get_param(config.mdl, 'modelworkspace');
        system_dimension = size(config.output_range, 1);
        assignin('base', 'SystemDimension', system_dimension);
        assignin('base', 'Formula', config.monitoringFormula);
        assignin('base', 'Preds', normal_preds);
      set_param([config.mdl, config.agentName], 'sample_time', num2str(config.sampleTime));
      set_param([config.mdl, config.agentName], 'input_range', mat2str(config.input_range));
      simulationArguments = { ...
          'SimulationMode', 'normal', ...
          'ReturnWorkspaceOutputs', 'on', ...
          'CaptureErrors', 'on', ...
          'SaveTime', 'on', ...
          'TimeSaveName', 'tout', ...
          'SaveState', 'on', ...
          'StateSaveName', 'xout', ...
          'SaveOutput', 'on', ...
          'OutputSaveName', 'yout', ...
          'SaveFormat', 'Dataset', ...
          'StartTime', '0.0', ...
          'StopTime', num2str(config.stopTime) ...
      };

      % Legacy Falsify experiments used a common absolute tolerance.  The
      % ARCH-COMP replay pipeline instead preserves each official model's
      % numerical configuration so wrapper and official trajectories are
      % compared under the same solver settings.
      useModelSolverSettings = ...
          isfield(config, 'useModelSolverSettings') && ...
          config.useModelSolverSettings;

      if ~useModelSolverSettings
          simulationArguments = [ ...
              simulationArguments, ...
              {'AbsTol', '1e-5'} ...
          ];
      end

      simOut = sim(config.mdl, simulationArguments{:});

      % -------------------------------------------------
      % Check whether the Simulink simulation itself failed.
      %
      % When CaptureErrors is "on", Simulink stores the
      % original error in simOut.ErrorMessage instead of
      % immediately throwing it.
      % -------------------------------------------------

      simulationError = string(simOut.ErrorMessage);

      if strlength(simulationError) > 0
          error( ...
              'Falsify:SimulationFailed', ...
              'Simulink simulation failed:\n%s', ...
              char(simulationError) ...
              );
      end

      % -------------------------------------------------
      % Verify that the outputs required by Falsify exist.
      % -------------------------------------------------

      availableOutputs = string(who(simOut));

      requiredOutputs = [
          "tout"
          "xout"
          "yout"
          ];

      missingOutputs = ...
          setdiff(requiredOutputs, availableOutputs);

      if ~isempty(missingOutputs)

          missingOutputText = strjoin( ...
              cellstr(missingOutputs), ...
              ', ' ...
              );

          if isempty(availableOutputs)
              availableOutputText = '(none)';
          else
              availableOutputText = strjoin( ...
                  cellstr(availableOutputs), ...
                  ', ' ...
                  );
          end

          error( ...
              'Falsify:MissingSimulationOutput', ...
              [ ...
              'Required simulation output(s) are missing: %s\n' ...
              'Available outputs: %s' ...
              ], ...
              missingOutputText, ...
              availableOutputText ...
              );
      end

      tout = get(simOut, 'tout');
      xout = get(simOut, 'xout');
      yout = get(simOut, 'yout');
    end

    currDir = pwd;
    addpath(currDir);
    P = py.sys.path;
    insert(P,int32(0),pwd);
    tmpDir = tempname;
    mkdir(tmpDir);
    cd(tmpDir);
    % Load the model on the worker
    load_system(config.mdl);
    bestRob = inf;
    normal_preds = normalize_pred(config.preds, config.output_range);
    if isfield(config, 'alpha')
        py.driver.start_learning(config.option,...
            size(config.output_range, 1), size(config.input_range, 1),...
            config.alpha);
    else
        py.driver.start_learning(config.option,...
            size(config.output_range, 1), size(config.input_range, 1), 1);
    end
    tic;


    for numEpisode=1:config.maxEpisodes
        [~, xout, yout] = runsim(config, normal_preds);
        [Y, T, R] = yout2TY(yout);
        rob = dp_taliro(config.targetFormula, normal_preds, Y, T, [], [], []);
        py.driver.stop_episode_and_train(Y(end, :), exp(- R) - 1);
        disp(['Current iteration: ', num2str(numEpisode), ', rob = ', num2str(rob)])
        if rob <= bestRob
            bestRob = rob;
            bestYout = yout;
            bestXout = xout;
            if rob < 0
                break;
            end
        end
    end
    elapsedTime = toc;
    cd(currDir);
    rmdir(tmpDir,'s');
    rmpath(currDir);
    close_system(config.mdl, 0);
end

classdef rl_agent_arch2025_linear < matlab.System & ...
        matlab.system.mixin.Propagates & ...
        matlab.system.mixin.CustomIcon & ...
        matlab.system.mixin.Nondirect & ...
        matlab.system.mixin.SampleTime
%RL_AGENT_ARCH2025_LINEAR Generic piecewise-linear Falsify agent.

    properties
        sample_time = 5.0;
        input_range = [0.0 1.0];
        observation_dimension = 1;
    end

    properties(DiscreteState)
        action;
        last_action;
        last_t;
    end

    methods(Access = protected)
        function resetImpl(obj)
            actionCount = size(obj.input_range, 1);
            actionNormalized = zeros(1, actionCount);
            coder.extrinsic('py.driver.act');
            actionNormalized = double(py.driver.act( ...
                -ones(1, obj.observation_dimension)));
            actionNormalized = reshape(actionNormalized, 1, actionCount);
            actionNormalized = min( ...
                ones(1, actionCount), ...
                max(-ones(1, actionCount), actionNormalized));
            obj.action = obj.denormalizeAction_(actionNormalized);
            obj.last_action = obj.action;
            obj.last_t = 0;
        end

        function setupImpl(obj)
            obj.resetImpl();
        end

        function action = outputImpl(obj, ~, ~)
            currentTime = getCurrentTime(obj);
            progress = (currentTime - obj.last_t) / obj.sample_time;
            action = ((1 - progress) * obj.last_action + ...
                progress * obj.action)';
        end

        function updateImpl(obj, state, reward)
            coder.extrinsic('py.driver.driver');
            currentTime = getCurrentTime(obj);

            if floor(currentTime / obj.sample_time) ~= ...
                    floor(obj.last_t / obj.sample_time)
                actionCount = size(obj.input_range, 1);
                actionNormalized = zeros(1, actionCount);
                actionNormalized = double(py.driver.driver( ...
                    state', reward(1)));
                actionNormalized = reshape( ...
                    actionNormalized, 1, actionCount);
                actionNormalized = min( ...
                    ones(1, actionCount), ...
                    max(-ones(1, actionCount), actionNormalized));
                obj.last_action = obj.action;
                obj.action = obj.denormalizeAction_(actionNormalized);
                obj.last_t = currentTime;
            end
        end

        function [sizeValue, dataType, complexity] = ...
                getDiscreteStateSpecificationImpl(obj, propertyName)
            switch propertyName
                case {'action', 'last_action'}
                    sizeValue = [1 size(obj.input_range, 1)];
                case 'last_t'
                    sizeValue = [1 1];
                otherwise
                    error('Unknown discrete state: %s', propertyName);
            end
            dataType = 'double';
            complexity = false;
        end

        function flag = isInputSizeMutableImpl(~, ~)
            flag = false;
        end

        function flag = isOutputFixedSizeImpl(~, ~)
            flag = true;
        end

        function count = getNumInputsImpl(~)
            count = 2;
        end

        function sizeValue = getOutputSizeImpl(obj)
            sizeValue = [size(obj.input_range, 1)];
        end

        function dataType = getOutputDataTypeImpl(~)
            dataType = 'double';
        end

        function flag = isOutputComplexImpl(~)
            flag = false;
        end

        function [stateDirect, rewardDirect] = ...
                isInputDirectFeedthroughImpl(~, ~, ~)
            stateDirect = false;
            rewardDirect = false;
        end

        function icon = getIconImpl(~)
            icon = 'ARCH 2025 linear agent';
        end
    end

    methods(Access = private)
        function action = denormalizeAction_(obj, normalized)
            lower = obj.input_range(:, 1)';
            upper = obj.input_range(:, 2)';
            middle = (lower + upper) / 2;
            action = normalized .* (upper - middle) + middle;
        end
    end
end

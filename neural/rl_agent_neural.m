classdef rl_agent_neural < matlab.System ...
        & matlab.system.mixin.Propagates ...
        & matlab.system.mixin.CustomIcon ...
        & matlab.system.mixin.Nondirect ...
        & matlab.system.mixin.SampleTime

    % =====================================================
    % Public properties
    % =====================================================

    properties

        % Interval at which the agent selects a new Ref value.
        sample_time = 5.0;

        % ARCH-COMP NN benchmark input range:
        %   1 <= Ref <= 3
        input_range = [1.0 3.0];
    end


    % =====================================================
    % Discrete states
    % =====================================================

    properties(DiscreteState)

        action;
        last_action;
        last_t;
    end


    % =====================================================
    % Protected System object methods
    % =====================================================

    methods(Access = protected)

        function resetImpl(obj)

            % Define a fixed-size double before assigning the
            % result returned by the Python interpreter.
            action_normalized = 0.0;

            coder.extrinsic('py.driver.act');

            % Initial normalized state:
            %   state(1) = normalized Pos
            %   state(2) = normalized Ref
            action_normalized = double( ...
                py.driver.act([-1.0 -1.0]) ...
            );

            action_normalized = min( ...
                1.0, ...
                max(-1.0, action_normalized) ...
            );

            lower = obj.input_range(1, 1);
            upper = obj.input_range(1, 2);
            middle = (lower + upper) / 2.0;

            obj.action = ...
                action_normalized * (upper - middle) ...
                + middle;

            obj.last_action = obj.action;
            obj.last_t = 0.0;
        end


        function setupImpl(obj)

            obj.resetImpl();
        end


        function action = outputImpl(obj, ~, ~)

            current_time = getCurrentTime(obj);

            interpolation_ratio = ...
                (current_time - obj.last_t) ...
                / obj.sample_time;

            action = ...
                (1.0 - interpolation_ratio) ...
                * obj.last_action ...
                + interpolation_ratio ...
                * obj.action;
        end


        function updateImpl(obj, state, reward)

            % Define a fixed-size double before assigning the
            % result returned by the Python interpreter.
            action_normalized = 0.0;

            coder.extrinsic('py.driver.driver');

            current_time = getCurrentTime(obj);

            current_segment = ...
                floor(current_time / obj.sample_time);

            previous_segment = ...
                floor(obj.last_t / obj.sample_time);

            if current_segment ~= previous_segment

                action_normalized = double( ...
                    py.driver.driver( ...
                        state', ...
                        reward(1) ...
                    ) ...
                );

                action_normalized = min( ...
                    1.0, ...
                    max(-1.0, action_normalized) ...
                );

                lower = obj.input_range(1, 1);
                upper = obj.input_range(1, 2);
                middle = (lower + upper) / 2.0;

                obj.last_action = obj.action;

                obj.action = ...
                    action_normalized ...
                    * (upper - middle) ...
                    + middle;

                obj.last_t = current_time;
            end
        end


        % =================================================
        % State specifications
        % =================================================

        function [size_value, data_type, complexity] = ...
                getDiscreteStateSpecificationImpl( ...
                    ~, ...
                    property_name ...
                )

            switch property_name

                case 'action'

                    size_value = [1];
                    data_type = 'double';
                    complexity = false;

                case 'last_action'

                    size_value = [1];
                    data_type = 'double';
                    complexity = false;

                case 'last_t'

                    size_value = [1];
                    data_type = 'double';
                    complexity = false;

                otherwise

                    size_value = [1];
                    data_type = 'double';
                    complexity = false;
            end
        end


        % =================================================
        % Input and output specifications
        % =================================================

        function flag = isInputSizeMutableImpl(~, ~)

            flag = false;
        end


        function flag = isOutputFixedSizeImpl(~, ~)

            flag = true;
        end


        function input_count = getNumInputsImpl(~)

            input_count = 2;
        end


        function output_size = getOutputSizeImpl(~)

            output_size = [1];
        end


        function data_type = getOutputDataTypeImpl(~)

            data_type = 'double';
        end


        function flag = isOutputComplexImpl(~)

            flag = false;
        end


        function icon = getIconImpl(~)

            icon = 'rl_agent_neural';
        end


        function [state_feedthrough, reward_feedthrough] = ...
                isInputDirectFeedthroughImpl(~, ~, ~)

            state_feedthrough = false;
            reward_feedthrough = false;
        end
    end


    % =====================================================
    % Display configuration
    % =====================================================

    methods(Static, Access = protected)

        function header = getHeaderImpl

            header = ...
                matlab.system.display.Header( ...
                    'rl_agent_neural' ...
                );
        end


        function group = getPropertyGroupsImpl

            group = ...
                matlab.system.display.Section( ...
                    'rl_agent_neural' ...
                );
        end
    end
end
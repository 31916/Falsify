classdef arch2025_sb_network < matlab.System & ...
        matlab.system.mixin.Propagates & ...
        matlab.system.mixin.SampleTime
%ARCH2025_SB_NETWORK Online adapter for a FalBenchGen LSTM network.

    properties(Nontunable)
        sample_time = 1.0;
        sequence_length = 24;
        output_dimension = 1;
        network_file = '';
    end

    methods(Access = protected)
        function output = stepImpl(obj, inputValue)
            coder.extrinsic('arch2025_sb_predict_step');
            output = zeros(obj.output_dimension, 1);
            firstOutput = 0.0;
            secondOutput = 0.0;
            [firstOutput, secondOutput] = arch2025_sb_predict_step( ...
                obj.network_file, ...
                double(inputValue), ...
                getCurrentTime(obj), ...
                obj.sequence_length, ...
                obj.output_dimension);
            output(1) = firstOutput;
            if obj.output_dimension > 1
                output(2) = secondOutput;
            end
        end

        function sampleTime = getSampleTimeImpl(obj)
            sampleTime = createSampleTime( ...
                obj, ...
                'Type', 'Discrete', ...
                'SampleTime', obj.sample_time, ...
                'OffsetTime', 0);
        end

        function flag = isInputSizeMutableImpl(~, ~)
            flag = false;
        end

        function flag = isOutputFixedSizeImpl(~, ~)
            flag = true;
        end

        function sizeValue = getOutputSizeImpl(obj)
            sizeValue = [obj.output_dimension];
        end

        function dataType = getOutputDataTypeImpl(~)
            dataType = 'double';
        end

        function flag = isOutputComplexImpl(~)
            flag = false;
        end

        function icon = getIconImpl(~)
            icon = 'FalBenchGen LSTM';
        end
    end
end

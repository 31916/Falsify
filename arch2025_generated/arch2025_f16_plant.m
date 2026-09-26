classdef arch2025_f16_plant < matlab.System & ...
        matlab.system.mixin.Propagates & ...
        matlab.system.mixin.SampleTime
%ARCH2025_F16_PLANT Simulink adapter for one official F-16 trajectory.

    properties(Nontunable)
        sample_time = 0.01;
        stop_time = 15.0;
        official_directory = '';
        compatibility_directory = '';
    end

    methods(Access = protected)
        function altitude = stepImpl(obj, initialAngles)
            coder.extrinsic('arch2025_f16_sample');
            altitude = 4040.0;
            altitude = arch2025_f16_sample( ...
                obj.official_directory, ...
                obj.compatibility_directory, ...
                double(initialAngles), ...
                getCurrentTime(obj), ...
                obj.stop_time);
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

        function sizeValue = getOutputSizeImpl(~)
            sizeValue = [1];
        end

        function dataType = getOutputDataTypeImpl(~)
            dataType = 'double';
        end

        function flag = isOutputComplexImpl(~)
            flag = false;
        end

        function icon = getIconImpl(~)
            icon = 'Official F-16 GCAS';
        end
    end
end

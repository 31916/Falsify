classdef fim_comparison_agent < matlab.System & matlab.system.mixin.Propagates & matlab.system.mixin.SampleTime
    % FIM-only synchronous observation/action bridge; original Falsify agents.
    % A Memory on the gear observation branch breaks the controller feedthrough.
    properties
        sample_time = 5;
        input_range = [60 100];
        stop_time = 30;
    end
    properties(DiscreteState)
        action;
        last_t;
    end
    methods(Access=protected)
        function resetImpl(obj)
            obj.action=mean(obj.input_range); obj.last_t=-obj.sample_time;
        end
        function setupImpl(obj)
            obj.resetImpl();
        end
        function output=stepImpl(obj,state)
            coder.extrinsic('py.fim_comparison_driver.action');
            t=getCurrentTime(obj);
            if t<obj.stop_time-1e-10 && t>obj.last_t+1e-10
                a=0; a=double(py.fim_comparison_driver.action(state',t));
                assert(isscalar(a) && isfinite(a) && a>=-1 && a<=1);
                obj.action=mean(obj.input_range)+a*diff(obj.input_range)/2;
                obj.last_t=t;
            end
            output=obj.action;
        end
        function sampleTime=getSampleTimeImpl(obj)
            sampleTime=createSampleTime(obj,'Type','Discrete','SampleTime',obj.sample_time,'OffsetTime',0);
        end
        function [s,d,c]=getDiscreteStateSpecificationImpl(~,~)
            s=[1 1]; d='double'; c=false;
        end
        function n=getNumInputsImpl(~), n=1; end
        function s=getOutputSizeImpl(~), s=[1 1]; end
        function d=getOutputDataTypeImpl(~), d='double'; end
        function c=isOutputComplexImpl(~), c=false; end
        function f=isOutputFixedSizeImpl(~), f=true; end
        function f=isInputSizeMutableImpl(~,~), f=false; end
    end
end

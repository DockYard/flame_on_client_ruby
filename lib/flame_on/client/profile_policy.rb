module FlameOn
  module Client
    class ProfilePolicy
      def initialize(configuration)
        @configuration = configuration
      end

      def engine_class
        case @configuration.mode
        when :sampling
          Engines::Sampling
        when :enhanced_sampling
          Engines::EnhancedSampling
        when :targeted_trace
          ensure_deep_trace_enabled!
          Engines::TargetedTrace
        when :debug_trace
          ensure_deep_trace_enabled!
          Engines::DebugTrace
        else
          raise ArgumentError, "unsupported profiling mode: #{@configuration.mode.inspect}"
        end
      end

      def production_safe_default?
        @configuration.mode == :sampling && @configuration.detail_level == :standard
      end

      private

      def ensure_deep_trace_enabled!
        return if @configuration.deep_trace_enabled

        raise ArgumentError, 'deep trace modes require deep_trace_enabled to be true'
      end
    end
  end
end

module FlameOn
  module Client
    module Engines
      class TargetedTrace < Base
        private

        def build_trace(**kwargs)
          trace = super
          trace[:trace] = {
            targeted: true,
            sample_rate: @configuration.deep_trace_sample_rate
          }
          trace
        end
      end
    end
  end
end

module FlameOn
  module Client
    module Engines
      class EnhancedSampling < Sampling
        private

        def build_trace(**kwargs)
          trace = super
          trace[:sampling] = {
            sample_rate_hz: @configuration.sample_rate_hz,
            profile_cpu: @configuration.profile_cpu,
            profile_wall: @configuration.profile_wall,
            profile_allocations: @configuration.profile_allocations
          }
          trace
        end
      end
    end
  end
end

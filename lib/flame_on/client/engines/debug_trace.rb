module FlameOn
  module Client
    module Engines
      class DebugTrace < TargetedTrace
        private

        def build_trace(**kwargs)
          trace = super
          trace[:trace][:debug] = true
          trace
        end
      end
    end
  end
end

module FlameOn
  module Client
    module Processors
      class ProfileProcessor
        def process(batch)
          batch.map do |trace|
            trace.merge(processed_at: Time.now.utc.iso8601(6))
          end
        end
      end
    end
  end
end

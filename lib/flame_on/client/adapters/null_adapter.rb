module FlameOn
  module Client
    module Adapters
      class NullAdapter
        attr_reader :batches, :error_batches

        def initialize
          @batches = []
          @error_batches = []
        end

        def send_batch(batch)
          @batches << batch
          :ok
        end

        def send_errors(batch)
          @error_batches << batch
          :ok
        end
      end
    end
  end
end

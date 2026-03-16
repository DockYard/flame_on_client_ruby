$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'minitest/autorun'
require 'flame_on/client'

module FlameOn
  module Client
    class SlowAdapter
      attr_reader :batches, :error_batches

      def initialize(delay: 0.2, fail: false)
        @delay = delay
        @fail = fail
        @batches = []
        @error_batches = []
      end

      def send_batch(batch)
        sleep(@delay)
        raise 'adapter failure' if @fail

        @batches << batch
        :ok
      end

      def send_errors(batch)
        sleep(@delay)
        raise 'adapter failure' if @fail

        @error_batches << batch
        :ok
      end
    end
  end
end

class Minitest::Test
  def setup
    FlameOn::Client.reset_configuration!
  end

  def teardown
    FlameOn::Client.stop
  end
end

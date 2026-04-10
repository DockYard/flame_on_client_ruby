module FlameOn
  module Client
    class CircuitBreaker
      def initialize
        @mutex = Mutex.new
        @disabled = false
      end

      def disabled?
        @mutex.synchronize { @disabled }
      end

      def disable!
        @mutex.synchronize { @disabled = true }
      end

      def enable!
        @mutex.synchronize { @disabled = false }
      end
    end
  end
end

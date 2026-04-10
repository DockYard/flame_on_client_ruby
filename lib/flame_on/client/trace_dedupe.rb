module FlameOn
  module Client
    class TraceDedupe
      DEFAULT_WINDOW_SECONDS = 60

      def initialize(window_seconds: DEFAULT_WINDOW_SECONDS)
        @mutex = Mutex.new
        @traces = {}
        @window_seconds = window_seconds
      end

      def should_trace?(identifier)
        return true unless FlameOn::Client.configuration.dedupe_enabled

        @mutex.synchronize do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          last_traced = @traces[identifier]

          if last_traced && (now - last_traced) < @window_seconds
            false
          else
            @traces[identifier] = now
            true
          end
        end
      end

      def sweep
        @mutex.synchronize do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          cutoff = now - @window_seconds
          @traces.delete_if { |_, timestamp| timestamp < cutoff }
        end
      end
    end
  end
end

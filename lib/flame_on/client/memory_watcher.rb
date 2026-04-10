module FlameOn
  module Client
    class MemoryWatcher
      DEFAULT_CHECK_INTERVAL = 5 # seconds
      DEFAULT_MAX_MEMORY_MB = nil # auto-detect

      def initialize(
        circuit_breaker:,
        trace_dedupe: nil,
        check_interval: DEFAULT_CHECK_INTERVAL,
        max_memory_mb: DEFAULT_MAX_MEMORY_MB
      )
        @circuit_breaker = circuit_breaker
        @trace_dedupe = trace_dedupe
        @check_interval = check_interval
        @max_memory_bytes = (max_memory_mb || detect_max_memory_mb) * 1024 * 1024
        @thread = nil
      end

      def start
        @thread = Thread.new { run_loop }
        @thread.abort_on_exception = false
        @thread.name = 'flame_on_memory_watcher'
      end

      def stop
        @thread&.kill
        @thread = nil
      end

      private

      def run_loop
        loop do
          sleep @check_interval
          check_memory
          @trace_dedupe&.sweep
        rescue StandardError => e
          # Don't crash the watcher thread
          FlameOn::Client.logger&.warn("[FlameOn] MemoryWatcher error: #{e.message}")
        end
      end

      def check_memory
        current = current_memory_bytes
        return unless current

        if current > @max_memory_bytes
          unless @circuit_breaker.disabled?
            @circuit_breaker.disable!
            FlameOn::Client.logger&.warn(
              "[FlameOn] Tracing disabled: memory #{current / 1024 / 1024}MB exceeds #{@max_memory_bytes / 1024 / 1024}MB limit"
            )
          end
        elsif current < @max_memory_bytes * 0.8
          if @circuit_breaker.disabled?
            @circuit_breaker.enable!
            FlameOn::Client.logger&.info("[FlameOn] Tracing re-enabled: memory below threshold")
          end
        end
      end

      def current_memory_bytes
        # Linux: read from /proc/self/status
        if File.exist?('/proc/self/status')
          File.read('/proc/self/status').match(/VmRSS:\s+(\d+)\s+kB/) do |m|
            m[1].to_i * 1024
          end
        else
          # macOS: use ps
          pid = Process.pid
          output = `ps -o rss= -p #{pid}`.strip
          output.empty? ? nil : output.to_i * 1024
        end
      rescue StandardError
        nil
      end

      def detect_max_memory_mb
        # Default to 80% of system memory, or 1024MB fallback
        total = total_system_memory_mb
        total ? (total * 0.8).to_i : 1024
      end

      def total_system_memory_mb
        if File.exist?('/proc/meminfo')
          File.read('/proc/meminfo').match(/MemTotal:\s+(\d+)\s+kB/) do |m|
            m[1].to_i / 1024
          end
        elsif RUBY_PLATFORM.include?('darwin')
          output = `sysctl -n hw.memsize`.strip
          output.empty? ? nil : output.to_i / 1024 / 1024
        end
      rescue StandardError
        nil
      end
    end
  end
end

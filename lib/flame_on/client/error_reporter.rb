module FlameOn
  module Client
    class ErrorReporter
      def initialize(adapter:, max_queue_size:, max_batch_size:, flush_interval_ms:, drop_policy:)
        @adapter = adapter
        @max_batch_size = max_batch_size
        @flush_interval = flush_interval_ms / 1000.0
        @buffer = AsyncBuffer.new(max_size: max_queue_size, drop_policy: drop_policy)
        @processor = Processors::IdentityProcessor.new
        @stats_mutex = Mutex.new
        @worker_mutex = Mutex.new
        reset_stats
      end

      def start
        @worker_mutex.synchronize do
          return if running?

          @stop_requested = false
          @worker = Thread.new { run_loop }
          @worker.name = 'flame_on_error_reporter' if @worker.respond_to?(:name=)
        end
      end

      def stop
        @worker_mutex.synchronize do
          @stop_requested = true
          @worker&.join(1)
          flush
          @worker = nil
        end
      end

      def enqueue(event)
        result = @buffer.push(event)

        @stats_mutex.synchronize do
          @stats[:queued] += 1 if result[:enqueued]
          @stats[:dropped] += 1 if result[:dropped]
        end

        result
      end

      def flush
        batch = drain_batch(block: false)
        ship(batch) unless batch.empty?
      end

      def stats
        @stats_mutex.synchronize do
          @stats.merge(queue_size: @buffer.size)
        end
      end

      private

      def running?
        @worker&.alive?
      end

      def run_loop
        until @stop_requested
          batch = drain_batch(block: true)
          ship(batch) unless batch.empty?
        end
      ensure
        batch = drain_batch(block: false)
        ship(batch) unless batch.empty?
      end

      def drain_batch(block:)
        items = []

        first = @buffer.pop(timeout: block ? @flush_interval : 0)
        items << first if first

        while items.length < @max_batch_size
          item = @buffer.pop(timeout: 0)
          break unless item

          items << item
        end

        items
      end

      def ship(batch)
        processed_batch = @processor.process(batch)
        @adapter.send_errors(processed_batch)

        @stats_mutex.synchronize do
          @stats[:batches_sent] += 1
          @stats[:events_sent] += processed_batch.length
        end
      rescue StandardError
        @stats_mutex.synchronize do
          @stats[:send_failures] += 1
        end
      end

      def reset_stats
        @stop_requested = false
        @stats = {
          queued: 0,
          dropped: 0,
          batches_sent: 0,
          events_sent: 0,
          send_failures: 0
        }
      end
    end
  end
end

module FlameOn
  module Client
    class AsyncBuffer
      def initialize(max_size:, drop_policy:)
        @max_size = max_size
        @drop_policy = drop_policy
        @mutex = Mutex.new
        @resource = ConditionVariable.new
        @items = []
      end

      def push(item)
        @mutex.synchronize do
          dropped = nil

          if @items.length >= @max_size
            case @drop_policy
            when :drop_oldest
              dropped = @items.shift
            when :drop_newest
              return { enqueued: false, dropped: item, size: @items.length }
            else
              raise ArgumentError, "unsupported drop policy: #{@drop_policy.inspect}"
            end
          end

          @items << item
          @resource.signal
          { enqueued: true, dropped: dropped, size: @items.length }
        end
      end

      def pop(timeout: nil)
        deadline = timeout ? monotonic_time + timeout : nil

        @mutex.synchronize do
          while @items.empty?
            return nil if timeout == 0

            if deadline
              remaining = deadline - monotonic_time
              return nil if remaining <= 0

              @resource.wait(@mutex, remaining)
            else
              @resource.wait(@mutex)
            end
          end

          @items.shift
        end
      end

      def size
        @mutex.synchronize { @items.length }
      end

      private

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

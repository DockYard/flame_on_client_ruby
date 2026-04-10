module FlameOn
  module Client
    class Configuration
      MODES = %i[sampling enhanced_sampling targeted_trace debug_trace].freeze
      DETAIL_LEVELS = %i[minimal standard detailed full].freeze
      DROP_POLICIES = %i[drop_oldest drop_newest].freeze

      attr_accessor :capture,
                    :mode,
                    :detail_level,
                    :sample_rate_hz,
                    :max_frames,
                    :profile_cpu,
                    :profile_wall,
                    :profile_allocations,
                    :max_queue_size,
                    :max_batch_size,
                    :flush_interval_ms,
                    :drop_policy,
                    :deep_trace_enabled,
                    :deep_trace_sample_rate,
                    :default_threshold_ms,
                    :platform,
                    :environment,
                    :service_name,
                    :release,
                    :adapter,
                    :processor,
                    :dedupe_enabled,
                    :dedupe_window_seconds,
                    :max_memory_mb,
                    :memory_check_interval

      def initialize
        @capture = false
        @mode = :sampling
        @detail_level = :standard
        @sample_rate_hz = 100
        @max_frames = 400
        @profile_cpu = true
        @profile_wall = true
        @profile_allocations = false
        @max_queue_size = 1_000
        @max_batch_size = 50
        @flush_interval_ms = 5_000
        @drop_policy = :drop_oldest
        @deep_trace_enabled = false
        @deep_trace_sample_rate = 0.0
        @default_threshold_ms = 0
        @platform = 'ruby'
        @environment = ENV['FLAME_ON_ENV'] || ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV'] || 'production'
        @service_name = ENV['FLAME_ON_SERVICE_NAME']
        @release = ENV['FLAME_ON_RELEASE']
        @adapter = Adapters::NullAdapter.new
        @processor = Processors::ProfileProcessor.new
        @dedupe_enabled = true
        @dedupe_window_seconds = 60
        @max_memory_mb = nil
        @memory_check_interval = 5
      end

      def validate!
        validate_inclusion!(:mode, mode, MODES)
        validate_inclusion!(:detail_level, detail_level, DETAIL_LEVELS)
        validate_inclusion!(:drop_policy, drop_policy, DROP_POLICIES)

        validate_integer!(:sample_rate_hz, sample_rate_hz, min: 1)
        validate_integer!(:max_frames, max_frames, min: 1)
        validate_integer!(:max_queue_size, max_queue_size, min: 1)
        validate_integer!(:max_batch_size, max_batch_size, min: 1)
        validate_integer!(:flush_interval_ms, flush_interval_ms, min: 1)
        validate_integer!(:default_threshold_ms, default_threshold_ms, min: 0)

        unless deep_trace_sample_rate.is_a?(Numeric) && deep_trace_sample_rate >= 0.0 && deep_trace_sample_rate <= 1.0
          raise ArgumentError, 'deep_trace_sample_rate must be between 0.0 and 1.0'
        end

        raise ArgumentError, 'adapter must respond to send_batch' unless adapter.respond_to?(:send_batch)

        raise ArgumentError, 'processor must respond to process' unless processor.respond_to?(:process)

        true
      end

      private

      def validate_inclusion!(name, value, allowed)
        return if allowed.include?(value)

        raise ArgumentError, "#{name} must be one of #{allowed.inspect}"
      end

      def validate_integer!(name, value, min:)
        return if value.is_a?(Integer) && value >= min

        raise ArgumentError, "#{name} must be an Integer >= #{min}"
      end
    end
  end
end

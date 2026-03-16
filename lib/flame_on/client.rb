require 'securerandom'
require 'time'
require 'uri'

$LOAD_PATH.unshift(File.expand_path('client/generated', __dir__))

require_relative 'client/version'
require_relative 'client/configuration'
require_relative 'client/profile_policy'
require_relative 'client/async_buffer'
require_relative 'client/reporter'
require_relative 'client/error_reporter'
require_relative 'client/capture_result'
require_relative 'client/engines/base'
require_relative 'client/engines/sampling'
require_relative 'client/engines/enhanced_sampling'
require_relative 'client/engines/targeted_trace'
require_relative 'client/engines/debug_trace'
require_relative 'client/processors/profile_processor'
require_relative 'client/processors/identity_processor'
require_relative 'client/adapters/null_adapter'
require 'google/protobuf/timestamp_pb'
require_relative 'client/generated/perftools/profiles/profile_pb'
require_relative 'client/generated/flameon_pb'
require_relative 'client/generated/flameon_services_pb'
require_relative 'client/pprof_encoder'
require_relative 'client/error_encoder'
require_relative 'client/error_event_builder'
require_relative 'client/adapters/grpc_adapter'
require_relative 'client/integrations/rack_middleware'
require_relative 'client/integrations/rails'

module FlameOn
  module Client
    class << self
      def configure
        yield(configuration)
        configuration.validate!
        restart_reporter_if_running
        configuration
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def reset_configuration!
        stop
        @configuration = Configuration.new
      end

      def capture(event_name, event_identifier, threshold_ms: nil, metadata: {}, &block)
        return yield unless configuration.capture

        start
        threshold_ms ||= configuration.default_threshold_ms

        result = engine.capture(event_name, event_identifier, threshold_ms: threshold_ms, metadata: metadata, &block)

        reporter.enqueue(result.trace) if result.trace

        result.value
      end

      def start
        configuration.validate!
        reporter.start
      end

      def stop
        @reporter&.stop
        @error_reporter&.stop
        @reporter = nil
        @error_reporter = nil
      end

      def flush
        reporter.flush
        @error_reporter&.flush
      end

      def stats
        reporter.stats
      end

      def report_error(exception, **attributes)
        configuration.validate!
        unless configuration.adapter.respond_to?(:send_errors)
          raise ArgumentError,
                'adapter must respond to send_errors'
        end

        event = ErrorEventBuilder.new(configuration).build(exception, **attributes)
        error_reporter.start
        error_reporter.enqueue(event)
        event[:event_id]
      end

      def error_stats
        unless @error_reporter
          return { queued: 0, dropped: 0, batches_sent: 0, events_sent: 0, send_failures: 0,
                   queue_size: 0 }
        end

        @error_reporter.stats
      end

      def engine
        @engine = build_engine
      end

      private

      def reporter
        @reporter ||= Reporter.new(
          adapter: configuration.adapter,
          processor: configuration.processor,
          max_queue_size: configuration.max_queue_size,
          max_batch_size: configuration.max_batch_size,
          flush_interval_ms: configuration.flush_interval_ms,
          drop_policy: configuration.drop_policy
        )
      end

      def error_reporter
        @error_reporter ||= ErrorReporter.new(
          adapter: configuration.adapter,
          max_queue_size: configuration.max_queue_size,
          max_batch_size: configuration.max_batch_size,
          flush_interval_ms: configuration.flush_interval_ms,
          drop_policy: configuration.drop_policy
        )
      end

      def build_engine
        ProfilePolicy.new(configuration).engine_class.new(configuration)
      end

      def restart_reporter_if_running
        if defined?(@reporter) && @reporter
          stop
          @engine = nil
          start if configuration.capture
        else
          @engine = nil
        end
      end
    end
  end
end

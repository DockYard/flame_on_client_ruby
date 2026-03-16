module FlameOn
  module Client
    module Engines
      class Base
        def initialize(configuration)
          @configuration = configuration
        end

        def capture(event_name, event_identifier, threshold_ms:, metadata:, &block)
          started_at = monotonic_time
          started_wall = Time.now.utc
          value, samples_data = collect_samples(event_name, event_identifier, &block)
          finished_at = monotonic_time
          duration_us = ((finished_at - started_at) * 1_000_000).to_i

          trace = nil
          if duration_us >= (threshold_ms * 1000)
            trace = build_trace(
              event_name: event_name,
              event_identifier: event_identifier,
              duration_us: duration_us,
              captured_at: started_wall,
              metadata: metadata,
              samples_data: finalize_samples(samples_data, event_name, event_identifier, duration_us)
            )
          end

          CaptureResult.new(value: value, trace: trace)
        end

        private

        def build_trace(event_name:, event_identifier:, duration_us:, captured_at:, metadata:, samples_data:)
          {
            trace_id: SecureRandom.uuid,
            event_name: event_name,
            event_identifier: event_identifier,
            duration_us: duration_us,
            captured_at: captured_at.iso8601(6),
            mode: @configuration.mode,
            detail_level: @configuration.detail_level,
            max_frames: @configuration.max_frames,
            metadata: metadata,
            samples: samples_data.fetch(:samples),
            sample_count: samples_data.fetch(:sample_count),
            sampling_interval_us: samples_data[:sampling_interval_us]
          }
        end

        def collect_samples(_event_name, _event_identifier)
          [yield, nil]
        end

        def finalize_samples(samples_data, event_name, event_identifier, duration_us)
          return samples_data if samples_data && samples_data.fetch(:sample_count, 0) > 0

          {
            samples: fallback_samples(event_name, event_identifier, duration_us),
            sample_count: 1,
            sampling_interval_us: duration_us
          }
        end

        def fallback_samples(event_name, event_identifier, duration_us)
          [{ stack_path: "#{event_name};#{event_identifier}", duration_us: duration_us }]
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end

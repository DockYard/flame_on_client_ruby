module FlameOn
  module Client
    module Engines
      class Sampling < Base
        private

        def collect_samples(_event_name, _event_identifier)
          target_thread = Thread.current
          interval = 1.0 / @configuration.sample_rate_hz
          running = true
          sampled_paths = Queue.new

          sampler_thread = Thread.new do
            while running
              locations = target_thread.backtrace_locations
              sampled_paths << normalize_stack(locations) if locations && !locations.empty?

              sleep(interval)
            end
          end

          value = yield
          [value, aggregate_samples(sampled_paths, interval)]
        ensure
          running = false
          sampler_thread&.join
        end

        def normalize_stack(locations)
          frames = locations.filter_map do |location|
            next if internal_frame?(location)

            file = File.basename(location.path || location.absolute_path || 'unknown')
            "#{file}:#{location.base_label}"
          end.first(@configuration.max_frames)

          return nil if frames.empty?

          frames.reverse.join(';')
        end

        def aggregate_samples(sampled_paths, interval)
          paths = []
          paths << sampled_paths.pop until sampled_paths.empty?

          if paths.empty?
            return {
              samples: [],
              sample_count: 0,
              sampling_interval_us: (interval * 1_000_000).to_i
            }
          end

          counts = paths.compact.each_with_object(Hash.new(0)) { |path, memo| memo[path] += 1 }
          interval_us = (interval * 1_000_000).to_i

          if counts.empty?
            return {
              samples: [],
              sample_count: 0,
              sampling_interval_us: interval_us
            }
          end

          {
            samples: counts.map do |stack_path, count|
              { stack_path: stack_path, duration_us: count * interval_us }
            end,
            sample_count: counts.values.sum,
            sampling_interval_us: interval_us
          }
        end

        def internal_frame?(location)
          path = location.path || location.absolute_path
          return false unless path

          path.include?('/lib/flame_on/client/')
        end
      end
    end
  end
end

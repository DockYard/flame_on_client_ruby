module FlameOn
  module Client
    class PprofEncoder
      def encode(trace)
        FlameOn::TraceProfile.new(
          trace_id: trace.fetch(:trace_id),
          event_name: trace.fetch(:event_name),
          event_identifier: trace.fetch(:event_identifier),
          profile: build_profile(trace.fetch(:samples))
        )
      end

      private

      def build_profile(samples)
        all_frames = samples.flat_map { |sample| sample.fetch(:stack_path).split(';') }.uniq
        string_table = ['', 'self_us', 'total_us', 'microseconds', *all_frames]
        string_index = string_table.each_with_index.to_h

        functions = all_frames.each_with_index.map do |frame, index|
          function_id = index + 1
          Perftools::Profiles::Function.new(
            id: function_id,
            name: string_index.fetch(frame),
            system_name: string_index.fetch(frame),
            filename: 0,
            start_line: 0
          )
        end

        frame_to_function_id = functions.each_with_object({}) do |function, mapping|
          mapping[string_table.fetch(function.name)] = function.id
        end

        locations = functions.map do |function|
          Perftools::Profiles::Location.new(
            id: function.id,
            line: [Perftools::Profiles::Line.new(function_id: function.id, line: 0)]
          )
        end

        proto_samples = samples.map do |sample|
          duration_us = sample.fetch(:duration_us)
          location_ids = sample.fetch(:stack_path).split(';').map { |frame| frame_to_function_id.fetch(frame) }.reverse

          Perftools::Profiles::Sample.new(
            location_id: location_ids,
            value: [duration_us, duration_us]
          )
        end

        Perftools::Profiles::Profile.new(
          string_table: string_table,
          sample_type: [
            Perftools::Profiles::ValueType.new(
              type: string_index.fetch('self_us'),
              unit: string_index.fetch('microseconds')
            ),
            Perftools::Profiles::ValueType.new(
              type: string_index.fetch('total_us'),
              unit: string_index.fetch('microseconds')
            )
          ],
          function: functions,
          location: locations,
          sample: proto_samples,
          duration_nanos: compute_duration_nanos(samples)
        )
      end

      def compute_duration_nanos(samples)
        return 0 if samples.empty?

        samples.max_by { |sample| sample.fetch(:duration_us) }.fetch(:duration_us) * 1000
      end
    end
  end
end

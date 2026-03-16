module FlameOn
  module Client
    class ErrorEncoder
      def encode(event)
        FlameOn::ErrorEvent.new(
          event_id: event[:event_id].to_s,
          occurred_at: encode_timestamp(event[:occurred_at]),
          platform: event[:platform].to_s,
          environment: event[:environment].to_s,
          service: event[:service].to_s,
          route: event[:route].to_s,
          release: event[:release].to_s,
          severity: event[:severity].to_s,
          message: event[:message].to_s,
          handled: !!event[:handled],
          trace_id: event[:trace_id].to_s,
          span_id: event[:span_id].to_s,
          fingerprint: Array(event[:fingerprint]).map(&:to_s),
          exceptions: Array(event[:exceptions]).map { |exception| encode_exception(exception) },
          request: encode_request(event[:request]),
          user: encode_user(event[:user]),
          breadcrumbs: Array(event[:breadcrumbs]).map { |breadcrumb| encode_breadcrumb(breadcrumb) },
          tags: encode_key_values(event[:tags]),
          contexts: encode_key_values(event[:contexts])
        )
      end

      private

      def encode_exception(exception)
        FlameOn::Exception.new(
          type: exception[:type].to_s,
          value: exception[:value].to_s,
          stack_trace: encode_stack_trace(exception[:stack_trace])
        )
      end

      def encode_stack_trace(stack_trace)
        FlameOn::StackTrace.new(
          frames: Array(stack_trace&.dig(:frames)).map { |frame| encode_stack_frame(frame) }
        )
      end

      def encode_stack_frame(frame)
        FlameOn::StackFrame.new(
          function: frame[:function].to_s,
          module: frame[:module].to_s,
          file: frame[:file].to_s,
          line: frame[:line].to_i,
          column: frame[:column].to_i,
          in_app: !!frame[:in_app],
          abs_path: frame[:abs_path].to_s,
          context_line: frame[:context_line].to_s,
          pre_context: Array(frame[:pre_context]).map(&:to_s),
          post_context: Array(frame[:post_context]).map(&:to_s)
        )
      end

      def encode_request(request)
        return nil unless request

        FlameOn::RequestContext.new(
          method: request[:method].to_s,
          url: request[:url].to_s,
          route: request[:route].to_s,
          headers: encode_key_values(request[:headers]),
          remote_addr: request[:remote_addr].to_s
        )
      end

      def encode_user(user)
        return nil unless user

        FlameOn::UserContext.new(
          id: user[:id].to_s,
          email: user[:email].to_s,
          username: user[:username].to_s,
          ip_address: user[:ip_address].to_s
        )
      end

      def encode_breadcrumb(breadcrumb)
        FlameOn::Breadcrumb.new(
          timestamp: encode_timestamp(breadcrumb[:timestamp]),
          category: breadcrumb[:category].to_s,
          message: breadcrumb[:message].to_s,
          type: breadcrumb[:type].to_s,
          level: breadcrumb[:level].to_s,
          data: encode_key_values(breadcrumb[:data])
        )
      end

      def encode_key_values(values)
        pairs = if values.is_a?(Hash)
                  values.map { |key, value| { key: key, value: value } }
                else
                  Array(values)
                end

        pairs.map do |pair|
          FlameOn::KeyValue.new(key: pair[:key].to_s, value: pair[:value].to_s)
        end
      end

      def encode_timestamp(value)
        return nil unless value

        time = value.is_a?(Time) ? value.utc : Time.parse(value.to_s).utc
        Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
      end
    end
  end
end

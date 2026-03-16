module FlameOn
  module Client
    class ErrorEventBuilder
      def initialize(configuration)
        @configuration = configuration
      end

      def build(exception, occurred_at: Time.now.utc, event_id: SecureRandom.uuid, platform: nil, environment: nil,
                service: nil, route: nil, release: nil, severity: 'error', message: nil, handled: true,
                trace_id: nil, span_id: nil, fingerprint: [], request: nil, user: nil, breadcrumbs: [],
                tags: {}, contexts: {})
        {
          event_id: event_id,
          occurred_at: occurred_at,
          platform: platform || @configuration.platform || 'ruby',
          environment: environment || @configuration.environment || 'production',
          service: service || @configuration.service_name || 'unknown',
          route: route || request&.dig(:route) || request&.dig('route') || extract_route_from_url(request),
          release: release || @configuration.release || 'unknown',
          severity: severity.to_s,
          message: message || exception.message.to_s,
          handled: handled,
          trace_id: trace_id.to_s,
          span_id: span_id.to_s,
          fingerprint: Array(fingerprint).map(&:to_s),
          exceptions: [build_exception(exception)],
          request: build_request(request),
          user: build_user(user),
          breadcrumbs: Array(breadcrumbs).map { |crumb| build_breadcrumb(crumb) },
          tags: key_value_pairs(tags),
          contexts: key_value_pairs(contexts)
        }
      end

      private

      def build_exception(exception)
        {
          type: exception.class.name,
          value: exception.message.to_s,
          stack_trace: {
            frames: Array(exception.backtrace).map { |frame| build_frame(frame) }
          }
        }
      end

      def build_frame(frame)
        location, function = frame.to_s.split(':in ', 2)
        path, line = location.to_s.split(':', 2)
        abs_path = path.to_s.empty? ? frame.to_s : path.to_s
        function_name = function.to_s.gsub(/\A[`']|[`']\z/, '')

        {
          function: function_name.empty? ? '<unknown>' : function_name,
          module: infer_module_name(abs_path),
          file: File.basename(abs_path),
          line: line.to_i,
          column: 0,
          in_app: in_app_frame?(abs_path),
          abs_path: abs_path,
          context_line: '',
          pre_context: [],
          post_context: []
        }
      end

      def infer_module_name(abs_path)
        return '' unless abs_path

        File.basename(abs_path, File.extname(abs_path)).split('_').map(&:capitalize).join
      end

      def in_app_frame?(abs_path)
        abs_path && !abs_path.include?('/gems/')
      end

      def build_request(request)
        return nil unless request

        source = stringify_keys(request)

        {
          method: source['method'].to_s,
          url: source['url'].to_s,
          route: source['route'].to_s,
          headers: key_value_pairs(source['headers'] || {}),
          remote_addr: source['remote_addr'].to_s
        }
      end

      def build_user(user)
        return nil unless user

        source = stringify_keys(user)

        {
          id: source['id'].to_s,
          email: source['email'].to_s,
          username: source['username'].to_s,
          ip_address: source['ip_address'].to_s
        }
      end

      def build_breadcrumb(breadcrumb)
        source = stringify_keys(breadcrumb)

        {
          timestamp: source['timestamp'],
          category: source['category'].to_s,
          message: source['message'].to_s,
          type: source['type'].to_s,
          level: source['level'].to_s,
          data: key_value_pairs(source['data'] || {})
        }
      end

      def key_value_pairs(values)
        stringify_keys(values).map do |key, value|
          { key: key.to_s, value: value.to_s }
        end
      end

      def stringify_keys(values)
        values.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value
        end
      end

      def extract_route_from_url(request)
        url = request&.dig(:url) || request&.dig('url')
        return '' if url.to_s.empty?

        URI.parse(url).path
      rescue URI::InvalidURIError
        ''
      end
    end
  end
end

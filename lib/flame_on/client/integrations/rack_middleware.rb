require 'rack'

module FlameOn
  module Client
    module Integrations
      def self.build_rack_stack(app, client: FlameOn::Client, capture_requests: true, capture_errors: true,
                                request_options: {}, error_options: {})
        wrapped = app
        wrapped = RackMiddleware.new(wrapped, client: client, **request_options) if capture_requests
        wrapped = RackErrorMiddleware.new(wrapped, client: client, **error_options) if capture_errors
        wrapped
      end

      class RackMiddleware
        DEFAULT_EVENT_NAME = 'rack.request'

        def initialize(app, client: FlameOn::Client, event_name: DEFAULT_EVENT_NAME, threshold_ms: nil,
                       identifier: nil, metadata: nil)
          @app = app
          @client = client
          @event_name = event_name
          @threshold_ms = threshold_ms
          @identifier = identifier || method(:default_identifier)
          @metadata = metadata || method(:default_metadata)
        end

        def call(env)
          @client.capture(@event_name, @identifier.call(env), threshold_ms: @threshold_ms,
                                                              metadata: @metadata.call(env)) do
            @app.call(env)
          end
        end

        private

        def default_identifier(env)
          method = env['REQUEST_METHOD'] || 'GET'
          path = env['PATH_INFO'] || '/'
          "#{method} #{path}"
        end

        def default_metadata(env)
          {
            'request_method' => env['REQUEST_METHOD'],
            'path' => env['PATH_INFO'],
            'query_string' => env['QUERY_STRING']
          }.compact
        end
      end

      class RackErrorMiddleware
        def initialize(app, client: FlameOn::Client, handled: false, route: nil, request: nil, tags: nil, contexts: nil)
          @app = app
          @client = client
          @handled = handled
          @route = route || proc { |env, _error| env['PATH_INFO'] }
          @request = request || method(:default_request)
          @tags = tags || proc { |_env, _error| {} }
          @contexts = contexts || proc { |_env, _error| {} }
        end

        def call(env)
          @app.call(env)
        rescue StandardError => e
          @client.report_error(
            e,
            handled: @handled,
            route: @route.call(env, e),
            request: @request.call(env, e),
            tags: @tags.call(env, e),
            contexts: @contexts.call(env, e)
          )
          raise
        end

        private

        def default_request(env, _error)
          {
            method: env['REQUEST_METHOD'],
            url: request_url(env),
            route: env['PATH_INFO'],
            headers: extract_headers(env),
            remote_addr: env['REMOTE_ADDR']
          }
        end

        def request_url(env)
          scheme = env['rack.url_scheme'] || 'http'
          host = env['HTTP_HOST'] || env['SERVER_NAME']
          path = env['PATH_INFO'] || '/'
          query = env['QUERY_STRING']
          return path if host.to_s.empty?

          url = "#{scheme}://#{host}#{path}"
          query.to_s.empty? ? url : "#{url}?#{query}"
        end

        def extract_headers(env)
          env.each_with_object({}) do |(key, value), headers|
            next unless key.start_with?('HTTP_')

            normalized = key.delete_prefix('HTTP_').downcase.split('_').join('-')
            headers[normalized] = value
          end
        end
      end
    end
  end
end

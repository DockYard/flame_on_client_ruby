module FlameOn
  module Client
    module Integrations
      module Rails
        def self.install!(app, client: FlameOn::Client, capture_requests: true, capture_errors: true,
                          request_options: {}, error_options: {})
          middleware = app.config.middleware

          if capture_errors
            middleware.use(RackErrorMiddleware, client: client,
                                                **self.error_options.merge(error_options))
          end
          if capture_requests
            middleware.use(RackMiddleware, client: client,
                                           **request_options_for(client).merge(request_options))
          end

          app
        end

        def self.error_options
          {
            route: ->(env, _error) { route_signature(env) },
            request: ->(env, _error) { build_request(env) },
            tags: ->(env, _error) { build_tags(env) }
          }
        end

        def self.request_options_for(_client)
          {
            event_name: 'rails.request',
            identifier: ->(env) { "#{env['REQUEST_METHOD'] || 'GET'} #{route_signature(env)}" },
            metadata: ->(env) { build_metadata(env) }
          }
        end

        def self.build_metadata(env)
          params = path_parameters(env)

          {
            'request_method' => env['REQUEST_METHOD'],
            'path' => env['PATH_INFO'],
            'query_string' => env['QUERY_STRING'],
            'controller' => params[:controller] || params['controller'],
            'action' => params[:action] || params['action'],
            'request_id' => env['action_dispatch.request_id']
          }.compact
        end

        def self.build_request(env)
          {
            method: env['REQUEST_METHOD'],
            url: request_url(env),
            route: route_signature(env),
            headers: extract_headers(env),
            remote_addr: env['REMOTE_ADDR']
          }
        end

        def self.build_tags(env)
          params = path_parameters(env)

          {
            'controller' => params[:controller] || params['controller'],
            'action' => params[:action] || params['action'],
            'request_id' => env['action_dispatch.request_id']
          }.compact
        end

        def self.route_signature(env)
          route_pattern = env['action_dispatch.route_uri_pattern']
          return route_pattern.spec.to_s if route_pattern.respond_to?(:spec)

          params = path_parameters(env)
          controller = params[:controller] || params['controller']
          action = params[:action] || params['action']
          return "#{controller}##{action}" if controller && action

          env['PATH_INFO'] || '/'
        end

        def self.path_parameters(env)
          env['action_dispatch.request.path_parameters'] || {}
        end

        def self.request_url(env)
          scheme = env['rack.url_scheme'] || 'http'
          host = env['HTTP_HOST'] || env['SERVER_NAME']
          path = env['PATH_INFO'] || '/'
          query = env['QUERY_STRING']
          return path if host.to_s.empty?

          url = "#{scheme}://#{host}#{path}"
          query.to_s.empty? ? url : "#{url}?#{query}"
        end

        def self.extract_headers(env)
          env.each_with_object({}) do |(key, value), headers|
            next unless key.start_with?('HTTP_')

            headers[key.delete_prefix('HTTP_').downcase.tr('_', '-')] = value
          end
        end
      end
    end
  end
end

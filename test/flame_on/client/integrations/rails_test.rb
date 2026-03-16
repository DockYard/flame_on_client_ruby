require 'test_helper'

class FlameOnClientRailsIntegrationTest < Minitest::Test
  FakeMiddlewareEntry = Struct.new(:middleware, :args, :kwargs, keyword_init: true)

  class FakeMiddlewareStack
    attr_reader :entries

    def initialize
      @entries = []
    end

    def use(middleware, *args, **kwargs)
      @entries << FakeMiddlewareEntry.new(middleware: middleware, args: args, kwargs: kwargs)
    end
  end

  class FakeRailsConfig
    attr_reader :middleware

    def initialize
      @middleware = FakeMiddlewareStack.new
    end
  end

  class FakeRailsApp
    attr_reader :config

    def initialize
      @config = FakeRailsConfig.new
    end
  end

  def test_install_adds_error_and_request_middlewares_with_rails_defaults
    app = FakeRailsApp.new

    FlameOn::Client::Integrations::Rails.install!(app)

    entries = app.config.middleware.entries
    request_options = entries[1].kwargs
    env = rails_env

    assert_equal FlameOn::Client::Integrations::RackErrorMiddleware, entries[0].middleware
    assert_equal FlameOn::Client::Integrations::RackMiddleware, entries[1].middleware
    assert_equal 'rails.request', request_options[:event_name]
    assert_equal 'POST users#show', request_options[:identifier].call(env)
    assert_equal 'users', request_options[:metadata].call(env)['controller']
    assert_equal 'show', request_options[:metadata].call(env)['action']
    assert_equal 'req-1', request_options[:metadata].call(env)['request_id']
  end

  def test_rails_error_defaults_report_controller_action_route_and_tags
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.service_name = 'web-app'
    end

    app = lambda do |_env|
      raise 'boom'
    end

    middleware = FlameOn::Client::Integrations::RackErrorMiddleware.new(
      app,
      **FlameOn::Client::Integrations::Rails.error_options
    )

    assert_raises(RuntimeError) do
      middleware.call(rails_env)
    end

    sleep(0.1)

    event = adapter.error_batches.first.first

    assert_equal 'users#show', event[:route]
    assert_equal 'users#show', event[:request][:route]
    assert_equal 'users', event[:tags].find { |tag| tag[:key] == 'controller' }[:value]
    assert_equal 'show', event[:tags].find { |tag| tag[:key] == 'action' }[:value]
    assert_equal 'req-1', event[:tags].find { |tag| tag[:key] == 'request_id' }[:value]
  end

  private

  def rails_env
    {
      'REQUEST_METHOD' => 'POST',
      'PATH_INFO' => '/users/42',
      'QUERY_STRING' => 'tab=profile',
      'HTTP_HOST' => 'example.test',
      'rack.url_scheme' => 'https',
      'action_dispatch.request.path_parameters' => {
        controller: 'users',
        action: 'show',
        id: '42',
        format: 'json'
      },
      'action_dispatch.request_id' => 'req-1'
    }
  end
end

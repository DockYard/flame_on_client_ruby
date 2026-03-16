require 'test_helper'
require 'rack/mock'

class FlameOnClientRackMiddlewareTest < Minitest::Test
  def test_wraps_rack_requests_in_capture
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.sample_rate_hz = 500
    end

    app = lambda do |_env|
      sleep(0.03)
      [200, { 'content-type' => 'text/plain' }, ['ok']]
    end

    middleware = FlameOn::Client::Integrations::RackMiddleware.new(app)
    response = middleware.call(Rack::MockRequest.env_for('/users/42?active=true', method: 'POST'))

    sleep(0.1)

    trace = adapter.batches.first.first

    assert_equal 200, response.first
    assert_equal 'rack.request', trace[:event_name]
    assert_equal 'POST /users/42', trace[:event_identifier]
    assert_equal 'POST', trace[:metadata]['request_method']
    assert_equal '/users/42', trace[:metadata]['path']
    assert_equal 'active=true', trace[:metadata]['query_string']
  end

  def test_reports_uncaught_exceptions_and_reraises
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.service_name = 'billing-api'
      config.environment = 'test'
      config.release = '2026.03.16'
    end

    app = lambda do |_env|
      raise 'boom'
    end

    middleware = FlameOn::Client::Integrations::RackErrorMiddleware.new(app)

    error = assert_raises(RuntimeError) do
      middleware.call(Rack::MockRequest.env_for('/checkout?promo=1', method: 'POST', 'HTTP_X_REQUEST_ID' => 'req-1'))
    end

    sleep(0.1)

    event = adapter.error_batches.first.first

    assert_equal 'boom', error.message
    assert_equal 'billing-api', event[:service]
    assert_equal 'test', event[:environment]
    assert_equal '/checkout', event[:route]
    assert_equal false, event[:handled]
    assert_equal 'POST', event[:request][:method]
    assert_equal 'req-1', event[:request][:headers].find { |header| header[:key] == 'x-request-id' }[:value]
  end

  def test_build_rack_stack_wraps_error_and_request_middlewares
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.service_name = 'billing-api'
    end

    app = lambda do |env|
      sleep(0.03)
      raise 'boom' if env['PATH_INFO'] == '/orders/1'

      [200, { 'content-type' => 'text/plain' }, ['ok']]
    end

    wrapped_app = FlameOn::Client::Integrations.build_rack_stack(app)

    response = wrapped_app.call(Rack::MockRequest.env_for('/orders', method: 'GET'))

    assert_raises(RuntimeError) do
      wrapped_app.call(Rack::MockRequest.env_for('/orders/1', method: 'DELETE'))
    end

    sleep(0.1)

    trace = adapter.batches.first.first
    event = adapter.error_batches.first.first

    assert_equal 200, response.first
    assert_equal 'GET /orders', trace[:event_identifier]
    assert_equal '/orders/1', event[:route]
    assert_equal 'DELETE', event[:request][:method]
  end
end

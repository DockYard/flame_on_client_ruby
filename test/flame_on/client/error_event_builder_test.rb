require 'test_helper'

class FlameOnClientErrorEventBuilderTest < Minitest::Test
  def test_builds_error_event_from_exception_and_configuration_defaults
    configuration = FlameOn::Client::Configuration.new
    configuration.platform = 'ruby'
    configuration.environment = 'test'
    configuration.service_name = 'billing-api'
    configuration.release = '2026.03.16'

    exception = build_exception
    occurred_at = Time.utc(2026, 3, 16, 12, 0, 0, 123_456)

    event = FlameOn::Client::ErrorEventBuilder.new(configuration).build(
      exception,
      occurred_at: occurred_at,
      handled: false,
      route: '/checkout',
      trace_id: 'trace-123',
      span_id: 'span-456',
      fingerprint: ['checkout-timeout'],
      request: {
        method: 'POST',
        url: 'https://example.test/checkout',
        headers: { 'x-request-id' => 'req-1' }
      },
      user: {
        id: 'user-1',
        email: 'user@example.test'
      },
      breadcrumbs: [
        {
          timestamp: Time.utc(2026, 3, 16, 11, 59, 0),
          category: 'job',
          message: 'started',
          level: 'info',
          data: { 'attempt' => 1 }
        }
      ],
      tags: { 'region' => 'iad' },
      contexts: { 'tenant' => 'acme' }
    )

    assert_equal 'ruby', event[:platform]
    assert_equal 'test', event[:environment]
    assert_equal 'billing-api', event[:service]
    assert_equal '2026.03.16', event[:release]
    assert_equal 'boom', event[:message]
    assert_equal false, event[:handled]
    assert_equal '/checkout', event[:route]
    assert_equal 'trace-123', event[:trace_id]
    assert_equal 'span-456', event[:span_id]
    assert_equal ['checkout-timeout'], event[:fingerprint]
    assert_equal occurred_at, event[:occurred_at]
    assert_equal 'RuntimeError', event[:exceptions].first[:type]
    assert_equal 'explode', event[:exceptions].first[:stack_trace][:frames].first[:function]
    assert_equal 'x-request-id', event[:request][:headers].first[:key]
    assert_equal 'user@example.test', event[:user][:email]
    assert_equal 'job', event[:breadcrumbs].first[:category]
    assert_equal 'iad', event[:tags].first[:value]
    assert_equal 'acme', event[:contexts].first[:value]
    refute_nil event[:event_id]
  end

  private

  def build_exception
    raise 'boom'
  rescue RuntimeError => e
    e.set_backtrace([
                      '/app/services/checkout.rb:27:in `explode`',
                      '/gems/rack-3.0.0/lib/rack.rb:12:in `call`'
                    ])
    e
  end
end

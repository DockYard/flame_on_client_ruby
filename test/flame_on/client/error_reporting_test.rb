require 'test_helper'

class FlameOnClientErrorReportingTest < Minitest::Test
  def test_report_error_enqueues_completed_event_without_waiting_for_slow_adapter
    adapter = FlameOn::Client::SlowAdapter.new(delay: 0.3)

    FlameOn::Client.configure do |config|
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.service_name = 'billing-api'
      config.environment = 'test'
      config.release = '2026.03.16'
    end

    exception = RuntimeError.new('boom')
    exception.set_backtrace(['/app/services/checkout.rb:27:in `explode`'])

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    event_id = FlameOn::Client.report_error(exception, handled: false, route: '/checkout')
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    sleep(0.4)

    assert_operator elapsed, :<, 0.15
    refute_nil event_id
    assert_equal 1, adapter.error_batches.length
    assert_equal 'billing-api', adapter.error_batches.first.first[:service]
    assert_equal '/checkout', adapter.error_batches.first.first[:route]
    assert_equal false, adapter.error_batches.first.first[:handled]
  ensure
    FlameOn::Client.stop
  end

  def test_error_send_failures_are_recorded_and_not_raised
    adapter = FlameOn::Client::SlowAdapter.new(delay: 0.01, fail: true)

    FlameOn::Client.configure do |config|
      config.adapter = adapter
      config.flush_interval_ms = 25
    end

    FlameOn::Client.report_error(RuntimeError.new('boom'))
    sleep(0.1)

    assert_equal 1, FlameOn::Client.error_stats[:send_failures]
  ensure
    FlameOn::Client.stop
  end
end

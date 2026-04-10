require 'test_helper'

class FlameOnClientTraceDedupeTest < Minitest::Test
  def test_first_trace_is_allowed
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 60)

    FlameOn::Client.configure do |config|
      config.dedupe_enabled = true
    end

    assert dedupe.should_trace?('GET /users')
  end

  def test_duplicate_within_window_is_rejected
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 60)

    FlameOn::Client.configure do |config|
      config.dedupe_enabled = true
    end

    assert dedupe.should_trace?('GET /users')
    refute dedupe.should_trace?('GET /users')
  end

  def test_different_identifiers_are_independent
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 60)

    FlameOn::Client.configure do |config|
      config.dedupe_enabled = true
    end

    assert dedupe.should_trace?('GET /users')
    assert dedupe.should_trace?('POST /users')
  end

  def test_allows_after_window_expires
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 0.05)

    FlameOn::Client.configure do |config|
      config.dedupe_enabled = true
    end

    assert dedupe.should_trace?('GET /users')
    refute dedupe.should_trace?('GET /users')

    sleep(0.06)

    assert dedupe.should_trace?('GET /users')
  end

  def test_sweep_removes_expired_entries
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 0.05)

    FlameOn::Client.configure do |config|
      config.dedupe_enabled = true
    end

    dedupe.should_trace?('GET /users')
    dedupe.should_trace?('POST /users')

    sleep(0.06)

    dedupe.sweep

    # After sweep, entries are gone so these should be allowed again
    assert dedupe.should_trace?('GET /users')
    assert dedupe.should_trace?('POST /users')
  end

  def test_skips_dedup_when_disabled
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 60)

    FlameOn::Client.configure do |config|
      config.dedupe_enabled = false
    end

    assert dedupe.should_trace?('GET /users')
    assert dedupe.should_trace?('GET /users')
  end

  def test_capture_skips_duplicate_trace_with_identifier
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.dedupe_enabled = true
      config.dedupe_window_seconds = 60
    end

    # First call should profile
    FlameOn::Client.capture('web.request', 'GET /users', identifier: 'GET /users') do
      sleep(0.02)
      :first
    end

    sleep(0.1)

    first_batch_count = adapter.batches.length

    # Second call with same identifier should skip profiling
    result = FlameOn::Client.capture('web.request', 'GET /users', identifier: 'GET /users') do
      :second
    end

    sleep(0.1)

    assert_equal :second, result
    assert_equal first_batch_count, adapter.batches.length
  end

  def test_capture_without_identifier_always_profiles
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.dedupe_enabled = true
    end

    FlameOn::Client.capture('web.request', 'GET /users') do
      sleep(0.02)
      :first
    end

    sleep(0.1)

    FlameOn::Client.capture('web.request', 'GET /users') do
      sleep(0.02)
      :second
    end

    sleep(0.1)

    # Both should have been profiled since no identifier was passed
    assert_operator adapter.batches.length, :>=, 2
  end
end

require 'test_helper'

class FlameOnClientCaptureTest < Minitest::Test
  def sampled_work
    sleep(0.03)
  end

  def test_capture_returns_block_value
    FlameOn::Client.configure do |config|
      config.capture = true
    end

    result = FlameOn::Client.capture('web.request', 'GET /users') { 'ok' }

    assert_equal 'ok', result
  end

  def test_capture_enqueues_completed_trace_without_waiting_for_slow_adapter
    adapter = FlameOn::Client::SlowAdapter.new(delay: 0.3)

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
    end

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = FlameOn::Client.capture('job.run', 'SyncUsers') do
      sleep(0.01)
      :done
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_equal :done, result
    assert_operator elapsed, :<, 0.15
  end

  def test_capture_drops_trace_below_threshold
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
    end

    FlameOn::Client.capture('web.request', 'GET /fast', threshold_ms: 100) do
      sleep(0.01)
      :ok
    end

    sleep(0.1)

    assert_equal [], adapter.batches
  end

  def test_enhanced_sampling_adds_sampling_metadata
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.mode = :enhanced_sampling
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.profile_allocations = true
    end

    FlameOn::Client.capture('web.request', 'GET /rich') do
      sleep(0.01)
      :ok
    end

    sleep(0.1)

    trace = adapter.batches.first.first
    assert_equal :enhanced_sampling, trace[:mode]
    assert_equal true, trace[:sampling][:profile_allocations]
  end

  def test_sampling_mode_captures_real_stack_samples
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
      config.sample_rate_hz = 500
    end

    FlameOn::Client.capture('web.request', 'GET /sampled') do
      sampled_work
      :ok
    end

    sleep(0.1)

    trace = adapter.batches.first.first

    assert_operator trace[:samples].length, :>=, 1
    assert_equal(true, trace[:samples].any? { |sample| sample[:stack_path].include?('sampled_work') })
    refute(trace[:samples].any? { |sample| sample[:stack_path].include?('sampling.rb') })
    assert_equal Integer, trace[:sample_count].class
    assert_operator trace[:sample_count], :>=, 1
  end
end

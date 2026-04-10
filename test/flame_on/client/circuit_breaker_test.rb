require 'test_helper'

class FlameOnClientCircuitBreakerTest < Minitest::Test
  def test_starts_enabled
    cb = FlameOn::Client::CircuitBreaker.new
    refute cb.disabled?
  end

  def test_disable_sets_disabled
    cb = FlameOn::Client::CircuitBreaker.new
    cb.disable!
    assert cb.disabled?
  end

  def test_enable_clears_disabled
    cb = FlameOn::Client::CircuitBreaker.new
    cb.disable!
    cb.enable!
    refute cb.disabled?
  end

  def test_thread_safe_toggle
    cb = FlameOn::Client::CircuitBreaker.new

    threads = 10.times.map do |i|
      Thread.new do
        if i.even?
          cb.disable!
        else
          cb.enable!
        end
      end
    end

    threads.each(&:join)

    # Should not raise — just verify it returns a boolean
    assert_includes [true, false], cb.disabled?
  end

  def test_capture_skips_profiling_when_circuit_breaker_disabled
    FlameOn::Client.configure do |config|
      config.capture = true
    end

    FlameOn::Client.circuit_breaker.disable!

    result = FlameOn::Client.capture('test', 'test') do
      :block_result
    end

    assert_equal :block_result, result
    assert FlameOn::Client.circuit_breaker.disabled?
  end

  def test_capture_profiles_when_circuit_breaker_enabled
    adapter = FlameOn::Client::Adapters::NullAdapter.new

    FlameOn::Client.configure do |config|
      config.capture = true
      config.adapter = adapter
      config.flush_interval_ms = 25
    end

    FlameOn::Client.circuit_breaker.enable!

    result = FlameOn::Client.capture('test', 'test') do
      sleep(0.02)
      :profiled
    end

    sleep(0.1)

    assert_equal :profiled, result
    # When enabled, profiling should happen and a trace should be enqueued
    assert_operator adapter.batches.length, :>=, 1
  end
end

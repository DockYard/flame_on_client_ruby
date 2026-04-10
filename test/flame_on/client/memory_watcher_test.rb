require 'test_helper'

class FlameOnClientMemoryWatcherTest < Minitest::Test
  def test_starts_and_stops_without_error
    cb = FlameOn::Client::CircuitBreaker.new
    watcher = FlameOn::Client::MemoryWatcher.new(
      circuit_breaker: cb,
      check_interval: 0.05,
      max_memory_mb: 1024
    )

    watcher.start
    sleep(0.1)
    watcher.stop

    # Should not raise, should complete cleanly
    refute cb.disabled?
  end

  def test_disables_circuit_breaker_when_memory_exceeds_limit
    cb = FlameOn::Client::CircuitBreaker.new

    # Set an impossibly low limit so current process memory exceeds it
    watcher = FlameOn::Client::MemoryWatcher.new(
      circuit_breaker: cb,
      check_interval: 0.05,
      max_memory_mb: 1 # 1MB — any Ruby process uses more than this
    )

    watcher.start
    sleep(0.15)
    watcher.stop

    assert cb.disabled?, 'Expected circuit breaker to be disabled when memory exceeds limit'
  end

  def test_reenables_circuit_breaker_when_memory_below_threshold
    cb = FlameOn::Client::CircuitBreaker.new

    # Set a very high limit so current process is well under 80%
    watcher = FlameOn::Client::MemoryWatcher.new(
      circuit_breaker: cb,
      check_interval: 0.05,
      max_memory_mb: 100_000 # 100GB — way above any process
    )

    cb.disable!
    watcher.start
    sleep(0.15)
    watcher.stop

    refute cb.disabled?, 'Expected circuit breaker to be re-enabled when memory is below 80% of limit'
  end

  def test_sweeps_trace_dedupe_on_each_cycle
    FlameOn::Client.configure do |config|
      config.dedupe_enabled = true
    end

    cb = FlameOn::Client::CircuitBreaker.new
    dedupe = FlameOn::Client::TraceDedupe.new(window_seconds: 0.05)

    dedupe.should_trace?('GET /users')

    watcher = FlameOn::Client::MemoryWatcher.new(
      circuit_breaker: cb,
      trace_dedupe: dedupe,
      check_interval: 0.05,
      max_memory_mb: 100_000
    )

    sleep(0.06) # Let the window expire

    watcher.start
    sleep(0.15) # Let the watcher cycle and sweep
    watcher.stop

    # After sweep, the entry should be gone
    assert dedupe.should_trace?('GET /users')
  end

  def test_configure_starts_memory_watcher
    FlameOn::Client.configure do |config|
      config.capture = true
      config.memory_check_interval = 1
    end

    assert_instance_of FlameOn::Client::MemoryWatcher, FlameOn::Client.memory_watcher
  end

  def test_stop_cleans_up_memory_watcher
    FlameOn::Client.configure do |config|
      config.capture = true
    end

    assert FlameOn::Client.memory_watcher
    FlameOn::Client.stop
    assert_nil FlameOn::Client.memory_watcher
  end
end

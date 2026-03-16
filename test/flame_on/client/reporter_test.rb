require 'test_helper'

class FlameOnClientReporterTest < Minitest::Test
  def build_reporter(adapter: FlameOn::Client::Adapters::NullAdapter.new, drop_policy: :drop_oldest, queue_size: 2,
                     batch_size: 10, flush_interval_ms: 25)
    FlameOn::Client::Reporter.new(
      adapter: adapter,
      processor: FlameOn::Client::Processors::ProfileProcessor.new,
      max_queue_size: queue_size,
      max_batch_size: batch_size,
      flush_interval_ms: flush_interval_ms,
      drop_policy: drop_policy
    )
  end

  def test_flushes_asynchronously_in_background
    adapter = FlameOn::Client::Adapters::NullAdapter.new
    reporter = build_reporter(adapter: adapter)
    reporter.start

    reporter.enqueue({ trace_id: '1', samples: [] })
    sleep(0.1)

    assert_equal 1, adapter.batches.length
    assert_equal 1, adapter.batches.first.length
  ensure
    reporter.stop
  end

  def test_drop_oldest_never_blocks_and_replaces_old_items
    reporter = build_reporter(flush_interval_ms: 10_000, queue_size: 2, drop_policy: :drop_oldest)

    first = reporter.enqueue({ trace_id: '1' })
    second = reporter.enqueue({ trace_id: '2' })
    third = reporter.enqueue({ trace_id: '3' })

    assert_equal true, first[:enqueued]
    assert_equal true, second[:enqueued]
    assert_equal true, third[:enqueued]
    assert_equal({ trace_id: '1' }, third[:dropped])
    assert_equal 1, reporter.stats[:dropped]
  ensure
    reporter.stop
  end

  def test_drop_newest_rejects_new_item_without_blocking
    reporter = build_reporter(flush_interval_ms: 10_000, queue_size: 1, drop_policy: :drop_newest)

    reporter.enqueue({ trace_id: '1' })
    result = reporter.enqueue({ trace_id: '2' })

    assert_equal false, result[:enqueued]
    assert_equal({ trace_id: '2' }, result[:dropped])
  ensure
    reporter.stop
  end

  def test_send_failures_are_recorded_and_not_raised
    adapter = FlameOn::Client::SlowAdapter.new(delay: 0.01, fail: true)
    reporter = build_reporter(adapter: adapter)
    reporter.start

    reporter.enqueue({ trace_id: '1', samples: [] })
    sleep(0.1)

    assert_equal 1, reporter.stats[:send_failures]
  ensure
    reporter.stop
  end
end

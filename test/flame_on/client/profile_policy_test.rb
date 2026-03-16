require 'test_helper'

class FlameOnClientProfilePolicyTest < Minitest::Test
  def test_sampling_maps_to_sampling_engine
    policy = FlameOn::Client::ProfilePolicy.new(FlameOn::Client.configuration)

    assert_equal FlameOn::Client::Engines::Sampling, policy.engine_class
    assert_equal true, policy.production_safe_default?
  end

  def test_enhanced_sampling_maps_to_enhanced_engine
    FlameOn::Client.configure do |config|
      config.mode = :enhanced_sampling
    end

    policy = FlameOn::Client::ProfilePolicy.new(FlameOn::Client.configuration)

    assert_equal FlameOn::Client::Engines::EnhancedSampling, policy.engine_class
    assert_equal false, policy.production_safe_default?
  end

  def test_debug_trace_maps_to_debug_engine_when_enabled
    FlameOn::Client.configure do |config|
      config.mode = :debug_trace
      config.deep_trace_enabled = true
    end

    policy = FlameOn::Client::ProfilePolicy.new(FlameOn::Client.configuration)

    assert_equal FlameOn::Client::Engines::DebugTrace, policy.engine_class
  end
end

require 'test_helper'

class FlameOnClientConfigurationTest < Minitest::Test
  def test_defaults_model_production_safe_sampling
    config = FlameOn::Client.configuration

    assert_equal false, config.capture
    assert_equal :sampling, config.mode
    assert_equal :standard, config.detail_level
    assert_equal 100, config.sample_rate_hz
    assert_equal :drop_oldest, config.drop_policy
    assert_equal false, config.deep_trace_enabled
  end

  def test_invalid_mode_is_rejected
    assert_raises(ArgumentError) do
      FlameOn::Client.configure do |config|
        config.mode = :unknown
      end
    end
  end

  def test_targeted_trace_requires_deep_trace_opt_in
    FlameOn::Client.configure do |config|
      config.mode = :targeted_trace
    end

    assert_raises(ArgumentError) do
      FlameOn::Client.send(:engine)
    end
  end
end

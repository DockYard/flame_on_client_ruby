require 'test_helper'

class FlameOnClientPprofEncoderTest < Minitest::Test
  def build_trace(samples: [{ stack_path: 'A;B', duration_us: 500 }, { stack_path: 'A', duration_us: 100 }])
    {
      trace_id: 'trace-123',
      event_name: 'web.request',
      event_identifier: 'GET /users',
      samples: samples
    }
  end

  def test_encodes_trace_profile_metadata
    result = FlameOn::Client::PprofEncoder.new.encode(build_trace)

    assert_instance_of FlameOn::TraceProfile, result
    assert_equal 'trace-123', result.trace_id
    assert_equal 'web.request', result.event_name
    assert_equal 'GET /users', result.event_identifier
  end

  def test_builds_pprof_profile_with_deduplicated_frames
    profile = FlameOn::Client::PprofEncoder.new.encode(build_trace).profile

    assert_instance_of Perftools::Profiles::Profile, profile
    assert_equal '', profile.string_table.first
    assert_equal 2, profile.function.length
    assert_equal 2, profile.location.length
    assert_equal 2, profile.sample.length
  end

  def test_uses_leaf_first_location_ids
    trace = build_trace(samples: [{ stack_path: 'root;middle;leaf', duration_us: 100 }])
    profile = FlameOn::Client::PprofEncoder.new.encode(trace).profile
    sample = profile.sample.first

    names_by_function_id = profile.function.each_with_object({}) do |function, map|
      map[function.id] = profile.string_table[function.name]
    end

    function_ids_by_location_id = profile.location.each_with_object({}) do |location, map|
      map[location.id] = location.line.first.function_id
    end

    names = sample.location_id.map do |location_id|
      names_by_function_id.fetch(function_ids_by_location_id.fetch(location_id))
    end

    assert_equal %w[leaf middle root], names
    assert_equal [100, 100], sample.value
  end
end

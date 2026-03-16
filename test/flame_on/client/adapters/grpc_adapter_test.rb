require 'test_helper'

class FlameOnClientGrpcAdapterTest < Minitest::Test
  class FakeStub
    attr_reader :requests

    def initialize
      @requests = []
    end

    def ingest(request, metadata:)
      @requests << { request: request, metadata: metadata }
      FlameOn::IngestResponse.new(success: true, ingested: request.traces.length, message: 'ok')
    end
  end

  class FakeErrorStub
    attr_reader :requests

    def initialize
      @requests = []
    end

    def ingest_errors(request, metadata:)
      @requests << { request: request, metadata: metadata }
      FlameOn::IngestErrorsResponse.new(success: true, ingested: request.events.length, warnings: [])
    end
  end

  def test_sends_trace_profiles_with_bearer_metadata
    stub = FakeStub.new
    adapter = FlameOn::Client::Adapters::GrpcAdapter.new(
      endpoint: 'localhost:50051',
      token: 'secret-token',
      stub: stub
    )

    response = adapter.send_batch([
                                    {
                                      trace_id: 'trace-123',
                                      event_name: 'web.request',
                                      event_identifier: 'GET /users',
                                      samples: [{ stack_path: 'A;B', duration_us: 250 }]
                                    }
                                  ])

    entry = stub.requests.first

    assert_equal true, response.success
    assert_equal({ 'authorization' => 'Bearer secret-token' }, entry[:metadata])
    assert_instance_of FlameOn::IngestRequest, entry[:request]
    assert_equal 1, entry[:request].traces.length
    assert_instance_of FlameOn::TraceProfile, entry[:request].traces.first
    assert_instance_of Perftools::Profiles::Profile, entry[:request].traces.first.profile
  end

  def test_sends_error_events_with_bearer_metadata
    error_stub = FakeErrorStub.new
    adapter = FlameOn::Client::Adapters::GrpcAdapter.new(
      endpoint: 'localhost:50051',
      token: 'secret-token',
      error_stub: error_stub
    )

    response = adapter.send_errors([
                                     {
                                       event_id: 'evt-123',
                                       occurred_at: Time.utc(2026, 3, 16, 12, 0, 0, 123_456),
                                       platform: 'ruby',
                                       environment: 'test',
                                       service: 'billing-api',
                                       route: '/checkout',
                                       release: '2026.03.16',
                                       severity: 'error',
                                       message: 'boom',
                                       handled: false,
                                       trace_id: 'trace-123',
                                       span_id: 'span-456',
                                       fingerprint: ['checkout-timeout'],
                                       exceptions: [
                                         {
                                           type: 'RuntimeError',
                                           value: 'boom',
                                           stack_trace: {
                                             frames: [
                                               {
                                                 function: 'perform',
                                                 module: 'CheckoutJob',
                                                 file: 'checkout_job.rb',
                                                 line: 27,
                                                 column: 0,
                                                 in_app: true,
                                                 abs_path: '/app/jobs/checkout_job.rb',
                                                 context_line: 'raise "boom"',
                                                 pre_context: ['def perform'],
                                                 post_context: ['end']
                                               }
                                             ]
                                           }
                                         }
                                       ],
                                       request: {
                                         method: 'POST',
                                         url: 'https://example.test/checkout',
                                         route: '/checkout',
                                         headers: { 'x-request-id' => 'req-1' },
                                         remote_addr: '127.0.0.1'
                                       },
                                       user: {
                                         id: 'user-1',
                                         email: 'user@example.test',
                                         username: 'demo',
                                         ip_address: '127.0.0.1'
                                       },
                                       breadcrumbs: [
                                         {
                                           timestamp: Time.utc(2026, 3, 16, 11, 59, 0),
                                           category: 'job',
                                           message: 'started',
                                           type: 'default',
                                           level: 'info',
                                           data: { 'attempt' => 1 }
                                         }
                                       ],
                                       tags: { 'region' => 'iad' },
                                       contexts: { 'tenant' => 'acme' }
                                     }
                                   ])

    entry = error_stub.requests.first
    event = entry[:request].events.first

    assert_equal true, response.success
    assert_equal({ 'authorization' => 'Bearer secret-token' }, entry[:metadata])
    assert_instance_of FlameOn::IngestErrorsRequest, entry[:request]
    assert_equal 1, entry[:request].events.length
    assert_instance_of FlameOn::ErrorEvent, event
    assert_equal 'ruby', event.platform
    assert_equal 'RuntimeError', event.exceptions.first.type
    assert_equal 'x-request-id', event.request.headers.first.key
    assert_equal 'iad', event.tags.first.value
    assert_equal 123_456_000, event.occurred_at.nanos
  end
end

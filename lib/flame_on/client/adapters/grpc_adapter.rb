module FlameOn
  module Client
    module Adapters
      class GrpcAdapter
        def initialize(endpoint:, token:, channel_credentials: :this_channel_is_insecure, stub: nil, error_stub: nil,
                       encoder: PprofEncoder.new, error_encoder: ErrorEncoder.new)
          @endpoint = endpoint
          @token = token
          @channel_credentials = channel_credentials
          @stub = stub
          @error_stub = error_stub
          @encoder = encoder
          @error_encoder = error_encoder
        end

        def send_batch(batch)
          request = FlameOn::IngestRequest.new(traces: batch.map { |trace| @encoder.encode(trace) })
          client.ingest(request, metadata: metadata)
        end

        def send_errors(batch)
          request = FlameOn::IngestErrorsRequest.new(events: batch.map { |event| @error_encoder.encode(event) })
          error_client.ingest_errors(request, metadata: metadata)
        end

        private

        def client
          @stub ||= FlameOn::FlameOnIngest::Stub.new(@endpoint, @channel_credentials)
        end

        def error_client
          @error_stub ||= FlameOn::FlameOnErrorIngest::Stub.new(@endpoint, @channel_credentials)
        end

        def metadata
          { 'authorization' => "Bearer #{@token}" }
        end
      end
    end
  end
end

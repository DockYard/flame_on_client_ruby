# FlameOn Client for Ruby

Production-oriented Ruby client for FlameOn with low-overhead profiling defaults and opt-in higher-detail modes.

## Design Goals

- Default to production-safe statistical profiling.
- Keep reporting asynchronous so requests and jobs do not wait on encoding or network I/O.
- Allow more detail when needed, with an explicit runtime overhead tradeoff.
- Keep mode and detail controls vendor-neutral in the code and configuration surface.

## Current API

```ruby
require "flame_on/client"

FlameOn::Client.configure do |config|
  config.capture = true
  config.mode = :sampling
  config.detail_level = :standard
  config.sample_rate_hz = 100
  config.max_queue_size = 1_000
  config.drop_policy = :drop_oldest
  config.profile_allocations = false
  config.service_name = 'billing-api'
  config.environment = ENV.fetch('APP_ENV', 'production')
  config.release = ENV.fetch('APP_RELEASE', 'dev')
  config.adapter = FlameOn::Client::Adapters::GrpcAdapter.new(
    endpoint: 'localhost:50051',
    token: ENV.fetch('FLAME_ON_INGEST_TOKEN')
  )
end

result = FlameOn::Client.capture("web.request", "GET /users/:id", threshold_ms: 500) do
  "ok"
end

FlameOn::Client.flush
FlameOn::Client.stop
```

## Error Reporting

The client can also ship handled or unhandled exceptions to the `flame_on.FlameOnErrorIngest/IngestErrors` RPC over the same asynchronous background path.

```ruby
begin
  raise 'checkout failed'
rescue => error
  FlameOn::Client.report_error(
    error,
    handled: true,
    route: '/checkout',
    trace_id: 'trace-123',
    request: {
      method: 'POST',
      url: 'https://app.example.test/checkout',
      headers: { 'x-request-id' => 'req-1' }
    },
    tags: { region: 'iad' },
    contexts: { tenant: 'acme' }
  )
end
```

- `report_error` builds the `ErrorEvent` payload from the Ruby exception and backtrace.
- request headers, breadcrumbs, tags, and contexts are encoded as repeated key/value pairs to match the server contract.
- `platform`, `environment`, `service_name`, and `release` default from configuration and can be overridden per call.
- error delivery failures are isolated from application code and tracked via `FlameOn::Client.error_stats`.

## Profiling Modes

### `:sampling`

Default mode. Intended for continuous production use with low overhead.

- runs a scoped sampling loop only while the capture block is executing
- samples the current thread stack at `sample_rate_hz`
- aggregates repeated stack paths into collapsed-stack samples for background encoding and shipping

### `:enhanced_sampling`

Adds more metadata and deeper capture settings while staying sampling-based.

### `:targeted_trace`

Higher-detail mode intended for selectively traced paths, not broad continuous use.

### `:debug_trace`

Highest-detail mode for temporary diagnostics.

## Detail Levels

### `:minimal`

Smaller payloads and lower overhead.

### `:standard`

Default detail level. Good balance for continuous production profiling.

### `:detailed`

More frames and metadata.

### `:full`

Largest payloads and highest runtime cost.

## Async Reporting

Completed traces are handed to a bounded in-memory queue. A background reporter thread batches, processes, and ships them asynchronously.

- The caller thread only performs capture and queue handoff.
- Queue overflow never blocks the caller.
- Overflow uses a configurable drop policy.
- Adapter failures are recorded in stats and never raised into application code.

## Sampling Behavior

The current sampler is a scoped thread-stack sampler.

- sampling starts when `FlameOn::Client.capture` enters the block
- sampling stops when the block exits
- stack snapshots are aggregated into collapsed stack paths
- if a capture finishes before any sample is observed, the client falls back to a synthetic event-level sample so the trace can still be reported

This keeps the default model lightweight and avoids deterministic per-call tracing on the hot path.

- internal client frames are filtered out of sampled stacks so profiles stay focused on application code

## Rack Integration

The client includes a Rack middleware wrapper for automatic request capture.

```ruby
use FlameOn::Client::Integrations::RackMiddleware
```

For uncaught exceptions, add the error middleware too:

```ruby
use FlameOn::Client::Integrations::RackErrorMiddleware
use FlameOn::Client::Integrations::RackMiddleware
```

Or build the full stack in one step:

```ruby
app = FlameOn::Client::Integrations.build_rack_stack(app)
```

For Rails, use the installer in an initializer:

```ruby
FlameOn::Client::Integrations::Rails.install!(Rails.application)
```

The Rails helper installs both middlewares, uses `rails.request` as the event name, derives request identifiers from `controller#action` when available, and tags error events with `controller`, `action`, and `request_id`.

By default it emits:

- event name: `rack.request`
- event identifier: `METHOD /path`
- metadata: request method, path, and query string

You can also customize it:

```ruby
use FlameOn::Client::Integrations::RackMiddleware,
  event_name: 'web.request',
  threshold_ms: 250,
  identifier: ->(env) { "#{env['REQUEST_METHOD']} #{env['PATH_INFO']}" },
  metadata: ->(env) { { 'host' => env['HTTP_HOST'] } }
```

`RackErrorMiddleware` reports the exception, includes request URL, method, path, headers, and remote address, then re-raises so your normal Rack error handling still applies.

## Configuration Reference

| Setting | Default | Description |
| --- | --- | --- |
| `capture` | `false` | Enables or disables capture entirely |
| `mode` | `:sampling` | Profiling strategy |
| `detail_level` | `:standard` | Payload fidelity |
| `sample_rate_hz` | `100` | Sampling frequency hint |
| `max_frames` | `400` | Maximum frame depth |
| `profile_cpu` | `true` | Capture CPU-oriented profiles |
| `profile_wall` | `true` | Capture wall-clock-oriented profiles |
| `profile_allocations` | `false` | Capture allocation profiling |
| `max_queue_size` | `1_000` | Reporter queue capacity |
| `max_batch_size` | `50` | Reporter batch size |
| `flush_interval_ms` | `5_000` | Background flush interval |
| `drop_policy` | `:drop_oldest` | Queue overflow behavior |
| `deep_trace_enabled` | `false` | Allows tracing-oriented engines |
| `deep_trace_sample_rate` | `0.0` | Fraction of captures eligible for deep tracing |
| `default_threshold_ms` | `0` | Drop traces below this duration |
| `platform` | `"ruby"` | Default error-reporting platform |
| `environment` | detected or `"production"` | Default error-reporting environment |
| `service_name` | `ENV['FLAME_ON_SERVICE_NAME']` | Default error-reporting service |
| `release` | `ENV['FLAME_ON_RELEASE']` | Default error-reporting release |
| `adapter` | `FlameOn::Client::Adapters::NullAdapter.new` | Async delivery adapter |
| `processor` | `FlameOn::Client::Processors::ProfileProcessor.new` | Background trace processor |

## gRPC Transport

The client includes an opt-in gRPC adapter for FlameOn ingestion. Completed traces are encoded into pprof `Profile` payloads and sent to the `flame_on.FlameOnIngest/Ingest` RPC with bearer-token metadata. Error events are sent to `flame_on.FlameOnErrorIngest/IngestErrors` with the same bearer-token metadata.

```ruby
FlameOn::Client.configure do |config|
  config.capture = true
  config.adapter = FlameOn::Client::Adapters::GrpcAdapter.new(
    endpoint: 'flameon.example.com:443',
    token: ENV.fetch('FLAME_ON_INGEST_TOKEN'),
    channel_credentials: :this_channel_is_insecure
  )
end
```

- pprof encoding runs on the background reporter thread
- error event encoding runs on a separate background reporter thread
- the caller thread still only does capture and queue handoff
- transport failures stay isolated from application code

## Status

This initial implementation provides:

- configuration and policy modeling
- mode selection
- manual capture API
- asynchronous bounded reporter
- non-blocking queue overflow handling
- adapter and processor interfaces
- real scoped stack sampling for `:sampling` and `:enhanced_sampling`
- pprof encoding and gRPC delivery support
- error event encoding and gRPC delivery support
- Rack middleware integration for automatic request capture

It does not yet include framework integrations, allocation sampling, or a native VM sampling extension.

## Development

Run the tests with:

```bash
ruby -Ilib:test -e 'Dir["test/**/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
```

## License

MIT. See `LICENSE`.

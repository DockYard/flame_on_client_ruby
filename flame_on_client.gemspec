require_relative 'lib/flame_on/client/version'

Gem::Specification.new do |spec|
  spec.name = 'flame_on_client'
  spec.version = FlameOn::Client::VERSION
  spec.authors = ['OpenCode']
  spec.email = ['noreply@example.com']

  spec.summary = 'Runtime performance client for FlameOn'
  spec.description = 'Production-oriented Ruby profiling client with configurable fidelity and asynchronous reporting.'
  spec.homepage = 'https://flameon.ai'
  spec.license = 'MIT'

  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir[
    'README.md',
    'Rakefile',
    'lib/**/*.rb',
    'test/**/*.rb'
  ]

  spec.require_paths = ['lib']

  spec.add_dependency 'google-protobuf', '~> 4.32'
  spec.add_dependency 'grpc', '~> 1.75'
  spec.add_dependency 'rack', '~> 3.0'

  spec.add_development_dependency 'grpc-tools', '~> 1.75'
  spec.add_development_dependency 'minitest', '~> 5.25'
end

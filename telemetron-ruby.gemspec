lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.name          = 'telemetron-client'
  s.version       =  '0.0.1'
  s.summary       = 'Telemetron Ruby Client'
  s.description   = 'Telemetron Ruby Client (https://telemetron.io)'
  s.license       = 'MIT'
  s.homepage      = 'https://bitbucket.org/mindera/telemetron-client-ruby'
  s.authors       = ['Miguel Fonseca']
  s.email         = 'miguel.fonseca@mindera.com'

  s.files         = Dir['lib/**/*.rb'] + Dir['bin/*']
  s.require_paths = ['lib']

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'minitest-reporters'
end

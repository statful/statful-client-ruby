lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.name          = 'statful-client'
  s.version       =  '1.0.0'
  s.summary       = 'Statful Ruby Client'
  s.description   = 'Statful Ruby Client (https://www.statful.com)'
  s.license       = 'MIT'
  s.homepage      = 'https://github.com/statful/statful-client-ruby'
  s.authors       = ['Miguel Fonseca']
  s.email         = 'miguel.fonseca@mindera.com'

  s.files         = Dir['lib/**/*.rb']
  s.require_paths = ['lib']

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'yard'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'minitest-reporters'
end

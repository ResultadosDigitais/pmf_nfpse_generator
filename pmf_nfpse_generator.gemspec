# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pmf_nfpse_generator/version'

Gem::Specification.new do |s|
  s.name          = 'pmf_nfpse_generator'
  s.version       = '0.1.0'
  s.date          = '2014-04-06'
  s.summary       = 'PMF (SC) NFPS-e Generator'
  s.description   = 'Gem to generate NFPS-e XML`s of Florianópolis, SC, Brazil'
  s.authors       = ['Pedro Bachiega']
  s.email         = 'pedro@pedrobachiega.com'
  s.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  s.require_paths = ['lib']
  s.homepage      = 'https://github.com/ResultadosDigitais/pmf_nfpse_generator'
  s.license       = 'MIT'

  # s.add_runtime_dependency "csv"
  s.add_runtime_dependency 'builder'
  s.add_runtime_dependency 'httparty'
  s.add_runtime_dependency 'i18n'
  s.add_runtime_dependency 'activemodel'

  s.add_development_dependency 'bundler', '~> 1.9'
  s.add_development_dependency 'rake', '~> 10.4'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
end

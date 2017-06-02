# frozen_string_literal: true
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "English"
require "dependabot/version"

summary = "Automated dependency management"

Gem::Specification.new do |spec|
  spec.name          = "dependabot-core"
  spec.version       = Dependabot::VERSION
  spec.authors       = ["Dependabot"]
  spec.email         = ["support@dependabot.com"]
  spec.summary       = summary
  spec.description   = summary
  spec.homepage      = "https://github.com/hmarr/dependabot-core"
  spec.licenses      = ["MIT"]

  spec.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "bundler", ">= 1.12.0"
  spec.add_dependency "excon", "~> 0.55"
  spec.add_dependency "gemnasium-parser", "~> 0.1"
  spec.add_dependency "gems", "~> 1.0"
  spec.add_dependency "octokit", "~> 4.6"

  spec.add_development_dependency "webmock", "~> 2.3.1"
  spec.add_development_dependency "rspec", "~> 3.5.0"
  spec.add_development_dependency "rspec-its", "~> 1.2.0"
  spec.add_development_dependency "rubocop", "~> 0.48.0"
  spec.add_development_dependency "rake"
end

# frozen_string_literal: true

require "find"
require "./lib/dependabot/version"

Gem::Specification.new do |spec|
  spec.name         = "dependabot-common"
  spec.version      = Dependabot::VERSION
  spec.summary      = "Shared code used between Dependabot package managers"
  spec.description  = "Automated dependency management for Ruby, JavaScript, "\
                      "Python, PHP, Elixir, Rust, Java, .NET, Elm and Go"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/dependabot/dependabot-core"
  spec.license      = "Nonstandard" # License Zero Prosperity Public License

  spec.require_path = "lib"
  spec.files        = []

  spec.required_ruby_version = ">= 2.5.0"
  spec.required_rubygems_version = ">= 2.7.3"

  spec.add_dependency "aws-sdk-codecommit", "~> 1.28"
  spec.add_dependency "aws-sdk-ecr", "~> 1.5"
  spec.add_dependency "bundler", ">= 1.16", "< 3.0.0"
  spec.add_dependency "commonmarker", ">= 0.20.1", "< 0.22.0"
  spec.add_dependency "docker_registry2", "~> 1.7", ">= 1.7.1"
  spec.add_dependency "excon", "~> 0.66"
  spec.add_dependency "gitlab", "4.15.0"
  spec.add_dependency "nokogiri", "~> 1.8"
  spec.add_dependency "octokit", "~> 4.6"
  spec.add_dependency "pandoc-ruby", "~> 2.0"
  spec.add_dependency "parseconfig", "~> 1.0"
  spec.add_dependency "parser", "~> 2.5"
  spec.add_dependency "toml-rb", ">= 1.1.2", "< 3.0"

  spec.add_development_dependency "byebug", "~> 11.0"
  spec.add_development_dependency "gpgme", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "rspec", "~> 3.8"
  spec.add_development_dependency "rspec-its", "~> 1.2"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.4"
  spec.add_development_dependency "rubocop", "~> 0.88.0"
  spec.add_development_dependency "vcr", "6.0.0"
  spec.add_development_dependency "webmock", "~> 3.4"

  next unless File.exist?("../.gitignore")

  ignores = File.readlines("../.gitignore").grep(/\S+/).map(&:chomp)

  next unless File.directory?("lib")

  Find.find("lib", "bin") do |path|
    if ignores.any? { |i| File.fnmatch(i, "/" + path, File::FNM_DOTMATCH) }
      Find.prune
    else
      spec.files << path unless File.directory?(path)
    end
  end
end

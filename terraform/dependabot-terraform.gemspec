# frozen_string_literal: true

require "find"
require "../lib/dependabot/version"

Gem::Specification.new do |spec|
  spec.name         = "dependabot-terraform"
  spec.version      = Dependabot::VERSION
  spec.summary      = "Terraform support for dependabot-core"
  spec.description  = "Automated dependency management for Ruby, JavaScript, "\
                      "Python, PHP, Elixir, Rust, Java, .NET, Elm and Go"

  spec.author       = "Dependabot"
  spec.email        = "support@dependabot.com"
  spec.homepage     = "https://github.com/hmarr/dependabot-core"
  spec.license      = "License Zero Prosperity Public License"

  spec.require_path = "lib"
  spec.files        = []

  if File.exist?("../.gitignore")
    ignores = File.readlines("../.gitignore").grep(/\S+/).map(&:chomp)
    if File.directory?("lib")
      Find.find("lib") do |path|
        if ignores.any? { |i| File.fnmatch(i, "/" + path, File::FNM_DOTMATCH) }
          Find.prune
        else
          spec.files << path unless File.directory?(path)
        end
      end
    end
  end

  spec.required_ruby_version = ">= 2.5.0"
  spec.required_rubygems_version = ">= 2.7.3"

  spec.add_dependency "dependabot-core", Dependabot::VERSION

  spec.add_development_dependency "byebug", "~> 10.0"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.8.0"
  spec.add_development_dependency "rspec-its", "~> 1.2.0"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.4"
  spec.add_development_dependency "rubocop", "~> 0.60.0"
  spec.add_development_dependency "vcr", "~> 4.0.0"
  spec.add_development_dependency "webmock", "~> 3.4.0"
end

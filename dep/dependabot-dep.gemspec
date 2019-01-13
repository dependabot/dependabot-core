# frozen_string_literal: true

require "find"

Gem::Specification.new do |spec|
  core_gemspec = Bundler.load_gemspec_uncached("../dependabot-core.gemspec")

  spec.name         = "dependabot-dep"
  spec.summary      = "Go dep support for dependabot-core"
  spec.version      = core_gemspec.version
  spec.description  = core_gemspec.description

  spec.author       = core_gemspec.author
  spec.email        = core_gemspec.email
  spec.homepage     = core_gemspec.homepage
  spec.license      = core_gemspec.license

  spec.require_path = "lib"
  spec.files        = []

  spec.required_ruby_version = core_gemspec.required_ruby_version
  spec.required_rubygems_version = core_gemspec.required_ruby_version

  spec.add_dependency "dependabot-core", Dependabot::VERSION

  core_gemspec.development_dependencies.each do |dep|
    spec.add_development_dependency dep.name, dep.requirement.to_s
  end

  next unless File.exist?("../.gitignore")

  ignores = File.readlines("../.gitignore").grep(/\S+/).map(&:chomp)

  next unless File.directory?("lib") && File.directory?("helpers")

  prefix = "/" + File.basename(File.expand_path(__dir__)) + "/"
  Find.find("lib", "helpers") do |path|
    if ignores.any? { |i| File.fnmatch(i, prefix + path, File::FNM_DOTMATCH) }
      Find.prune
    else
      spec.files << path unless File.directory?(path)
    end
  end
end

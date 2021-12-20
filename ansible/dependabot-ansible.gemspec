# frozen_string_literal: true

require "find"

Gem::Specification.new do |spec|
  common_gemspec =
    Bundler.load_gemspec_uncached("../common/dependabot-common.gemspec")

  spec.name         = "dependabot-ansible"
  spec.summary      = "Ansible Galaxy support for dependabot"
  spec.version      = common_gemspec.version
  spec.description  = common_gemspec.description

  spec.author       = common_gemspec.author
  spec.email        = common_gemspec.email
  spec.homepage     = common_gemspec.homepage
  spec.license      = common_gemspec.license

  spec.require_path = "lib"
  spec.files        = []

  spec.required_ruby_version = common_gemspec.required_ruby_version
  spec.required_rubygems_version = common_gemspec.required_ruby_version

  spec.add_dependency "dependabot-common", Dependabot::VERSION

  common_gemspec.development_dependencies.each do |dep|
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

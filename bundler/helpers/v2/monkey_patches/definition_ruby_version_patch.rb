# frozen_string_literal: true

require "bundler/definition"

module BundlerDefinitionRubyVersionPatch
  def source_requirements
    if ruby_version
      requested_version = ruby_version.gem_version
      sources.metadata_source.specs <<
        Gem::Specification.new("Ruby\0", requested_version)
    end

    %w(2.5.3 2.6.10 2.7.7 3.0.5).each do |version|
      sources.metadata_source.specs << Gem::Specification.new("Ruby\0", version)
    end

    super
  end

  def metadata_dependencies
    @metadata_dependencies ||=
      [
        Bundler::Dependency.new("Ruby\0", ruby_version_requirements),
        Bundler::Dependency.new("RubyGems\0", Gem::VERSION)
      ]
  end

  def ruby_version_requirements
    return [] unless ruby_version

    ruby_version.versions.map do |version|
      Gem::Requirement.new(version)
    end
  end
end

Bundler::Definition.prepend(BundlerDefinitionRubyVersionPatch)

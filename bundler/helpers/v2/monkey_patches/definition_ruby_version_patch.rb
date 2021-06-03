# frozen_string_literal: true

require "bundler/definition"

module BundlerDefinitionRubyVersionPatch
  def source_requirements
    if ruby_version
      requested_version = ruby_version.to_gem_version_with_patchlevel
      sources.metadata_source.specs <<
        Gem::Specification.new("Ruby\0", requested_version)
    end

    sources.metadata_source.specs <<
      Gem::Specification.new("Ruby\0", "2.5.3p105")

    super
  end
end

Bundler::Definition.prepend(BundlerDefinitionRubyVersionPatch)

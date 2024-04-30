# typed: false
# frozen_string_literal: true

require "bundler/definition"

module BundlerDefinitionRubyVersionPatch
  def index
    @index ||= super.tap do
      if ruby_version
        requested_version = ruby_version.to_gem_version_with_patchlevel
        sources.metadata_source.specs <<
          Gem::Specification.new("ruby\0", requested_version)
      end

      %w(2.5.3p105 2.6.10p210 2.7.6p219 3.0.7 3.1.5 3.2.4).each do |version|
        sources.metadata_source.specs << Gem::Specification.new("ruby\0", version)
      end
    end
  end
end

Bundler::Definition.prepend(BundlerDefinitionRubyVersionPatch)

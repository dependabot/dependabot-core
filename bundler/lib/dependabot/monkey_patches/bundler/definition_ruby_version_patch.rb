# frozen_string_literal: true

module BundlerDefinitionRubyVersionPatch
  def index
    @index ||= super.tap do
      if ruby_version
        requested_version = ruby_version.to_gem_version_with_patchlevel
        sources.metadata_source.specs <<
          Gem::Specification.new("ruby\0", requested_version)
      end

      sources.metadata_source.specs <<
        Gem::Specification.new("ruby\0", "2.5.3p105")
    end
  end
end
Bundler::Definition.prepend(BundlerDefinitionRubyVersionPatch)

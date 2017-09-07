# frozen_string_literal: true
module BundlerDefinitionVersionPatch
  def index
    @index ||= super.tap do
      if ruby_version
        requested_version = ruby_version.to_gem_version_with_patchlevel
        sources.metadata_source.specs <<
          Gem::Specification.new("ruby\0", requested_version)
      end
    end
  end
end
Bundler::Definition.prepend(BundlerDefinitionVersionPatch)

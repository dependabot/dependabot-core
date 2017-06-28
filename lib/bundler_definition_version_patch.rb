# frozen_string_literal: true
module BundlerDefinitionVersionPatch
  def index
    @index ||= super.tap do |index|
      if ruby_version
        requested_version = ruby_version.to_gem_version_with_patchlevel
        index << Gem::Specification.new("ruby\0", requested_version)
      end
    end
  end
end
Bundler::Definition.prepend(BundlerDefinitionVersionPatch)

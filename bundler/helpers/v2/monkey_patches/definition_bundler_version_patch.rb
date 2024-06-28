# typed: false
# frozen_string_literal: true

require "bundler/definition"

module BundlerDefinitionBundlerVersionPatch
  # Ignore the Bundler version specified in the Gemfile (since the only Bundler
  # version available to us is the one we're using).
  def expanded_dependencies
    if @locked_bundler_version && @locked_bundler_version >= Gem::Version.new("2")
      @expanded_dependencies ||= (dependencies + metadata_dependencies).reject { |d| d.name == "bundler" }
    else
      super
    end
  end

  def dup_for_full_unlock
    if @locked_bundler_version && @locked_bundler_version >= Gem::Version.new("2")
      super
    else
      dupped_definition = super
      dupped_definition.instance_variable_set(:@unlocking_bundler, @unlocking_bundler)
      dupped_definition
    end
  end
end

Bundler::Definition.prepend(BundlerDefinitionBundlerVersionPatch)

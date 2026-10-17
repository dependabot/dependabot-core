# typed: false
# frozen_string_literal: true

require "bundler/source"

# The running Bundler is never locked as a gem, so its own Ruby requirement must
# not constrain gems that depend on bundler (e.g. rails, fastlane). See #12114.
module BundlerSourceMetadataBundlerRubyVersionPatch
  def specs
    @specs ||= super.tap do |index|
      index.search("bundler").each { |spec| spec.required_ruby_version = Gem::Requirement.default }
    end
  end
end

Bundler::Source::Metadata.prepend(BundlerSourceMetadataBundlerRubyVersionPatch)

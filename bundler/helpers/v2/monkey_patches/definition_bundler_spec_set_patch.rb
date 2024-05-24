# typed: false
# frozen_string_literal: true

require "bundler/spec_set"

# monkey patch materialized_for_all_platforms for lazy specification issue resolution
# https://github.com/dependabot/dependabot-core/pull/9807
module BundlerSpecSetPatch
  def materialized_for_all_platforms
    @specs.map do |s|
      next s unless s.is_a?(Bundler::LazySpecification)

      s.source.cached!
      s.source.remote!
      spec = s.materialize_for_installation
      raise Bundler::GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec

      spec
    end
  end
end

Bundler::SpecSet.prepend(BundlerSpecSetPatch)

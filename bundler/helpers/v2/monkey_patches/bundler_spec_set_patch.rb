# typed: false
# frozen_string_literal: true

require "bundler/definition"

# description needs update
#
module BundlerSpecSetPatch
  def materialized_for_all_platforms
    @specs.map do |s|
      next s unless s.is_a?(LazySpecification)

      s.source.cached!
      s.source.remote!
      spec = s.materialize_for_installation
      raise GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec

      spec
    end
  end
end

Bundler::SpecSet.prepend(BundlerSpecSetPatch)

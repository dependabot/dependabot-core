# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/julia/version"
require "sorbet-runtime"

module Dependabot
  module Julia
    class Dependency < Dependabot::Dependency
      extend T::Sig

      # This class intentionally delegates most functionality to the base
      # Dependabot::Dependency class.
      #
      # Note: Dependabot::Julia::Version is properly registered for the "julia" package manager
      # and implements ::new(version_string) and ::correct?(version_string) methods that handle
      # Julia version strings according to Julia's semantic versioning specification.
    end
  end
end

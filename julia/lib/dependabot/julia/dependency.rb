# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/julia/version"
require "sorbet-runtime"

module Dependabot
  module Julia
    class Dependency < Dependabot::Dependency
      extend T::Sig

      sig { override.returns(T.class_of(Dependabot::Julia::Version)) }
      def version_class
        Version
      end

      sig { returns(T.nilable(Dependabot::Julia::Version)) }
      def numeric_version
        @numeric_version ||= T.let(version_class.new(T.must(version)), T.nilable(Dependabot::Julia::Version))
      rescue ArgumentError
        nil
      end
    end
  end
end

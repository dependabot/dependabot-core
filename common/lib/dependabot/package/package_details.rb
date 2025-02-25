# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"
require "dependabot/package/package_release"

# Stores metadata for a package, including all its available versions
module Dependabot
  module Package
    class PackageDetails
      extend T::Sig

      sig do
        params(
          dependency: Dependabot::Dependency,
          releases: T::Array[Dependabot::Package::PackageRelease]
        ).void
      end
      def initialize(dependency:, releases: [])
        @dependency = T.let(dependency, Dependabot::Dependency)
        @releases = T.let(
          releases.sort_by(&:version).reverse,
          T::Array[Dependabot::Package::PackageRelease]
        )
      end

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
      attr_reader :releases
    end
  end
end

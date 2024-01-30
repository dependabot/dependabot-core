# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module UpdateCheckers
    module VersionFilters
      extend T::Sig

      sig do
        params(
          versions_array: T::Array[T.any(Gem::Version, T::Hash[Symbol, Gem::Version])],
          security_advisories: T::Array[SecurityAdvisory]
        )
          .returns(T::Array[T.any(Gem::Version, T::Hash[Symbol, Gem::Version])])
      end
      def self.filter_vulnerable_versions(versions_array, security_advisories)
        versions_array.reject do |v|
          security_advisories.any? do |a|
            if v.is_a?(Gem::Version)
              a.vulnerable?(v)
            else
              a.vulnerable?(v.fetch(:version))
            end
          end
        end
      end
    end
  end
end

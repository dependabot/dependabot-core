# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module UpdateCheckers
    module VersionFilters
      extend T::Sig

      sig do
        # Tricky generics explanation:
        # There's a type T that is either a Gem::Version or a Hash with a :version key
        # The method returns an array of T
        # So whichever is provided as input, the output will be an array of the same type.
        # https://sorbet.org/docs/generics#placing-bounds-on-generic-methods
        type_parameters(:T)
          .params(
            versions_array: T::Array[
              T.any(
                T.all(T.type_parameter(:T), Gem::Version),
                T.all(T.type_parameter(:T), T::Hash[Symbol, Gem::Version])
              )],
            security_advisories: T::Array[SecurityAdvisory]
          )
          .returns(T::Array[T.type_parameter(:T)])
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

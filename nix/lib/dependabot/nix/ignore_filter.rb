# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/requirement"

module Dependabot
  module Nix
    # Tests YY.MM version strings against Dependabot ignore conditions.
    class IgnoreFilter
      extend T::Sig

      sig { params(ignored_versions: T::Array[String]).void }
      def initialize(ignored_versions)
        @ignored_versions = ignored_versions
        @requirements = T.let(nil, T.nilable(T::Array[Gem::Requirement]))
      end

      sig { params(version_str: T.nilable(String)).returns(T::Boolean) }
      def ignored?(version_str)
        return false unless version_str
        return false if requirements.empty?

        gem_version = Gem::Version.new(version_str)
        requirements.any? { |req| req.satisfied_by?(gem_version) }
      end

      private

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig { returns(T::Array[Gem::Requirement]) }
      def requirements
        @requirements ||= ignored_versions.flat_map do |req|
          Dependabot::Nix::Requirement.requirements_array(req)
        rescue Gem::Requirement::BadRequirementError
          []
        end
      end
    end
  end
end

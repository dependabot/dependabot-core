# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Bundler
    class Requirement < Dependabot::Requirement
      extend T::Sig

      GEM_DEP_SPLIT = T.let(/\A(?<name>[a-zA-Z0-9_\-]+):(?<version>.+)\z/, Regexp)

      sig { params(req: T::Hash[Symbol, String], version: Gem::Version).returns(T::Boolean) }
      def self.satisfied_by?(req, version)
        new(req[:requirement]).satisfied_by?(version)
      end

      # For consistency with other languages, we define a requirements array.
      # Ruby doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(dep_string: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def self.parse_dep_string(dep_string)
        stripped = dep_string.strip
        return nil if stripped.empty?

        match = stripped.match(GEM_DEP_SPLIT)
        return nil unless match

        name = T.must(match[:name])
        constraint = T.must(match[:version]).strip

        return nil if constraint.empty?

        version = extract_version(constraint)

        {
          name: name,
          normalised_name: name,
          version: version,
          requirement: constraint,
          extras: nil
        }
      end

      sig { params(constraint: String).returns(T.nilable(String)) }
      def self.extract_version(constraint)
        version_part = constraint.sub(/\A[~><=!]+\s*/, "").strip

        return version_part if version_part.match?(/\A\d+(?:\.\d+)*(?:\.\w+)?\z/)

        nil
      end

      private_class_method :extract_version

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          T.must(req_string).split(",").map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("bundler", Dependabot::Bundler::Requirement)

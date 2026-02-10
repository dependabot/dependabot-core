# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/go_modules/version"

module Dependabot
  module GoModules
    class RequirementParser
      extend T::Sig

      # Go module paths follow the pattern: host/path/segments
      # Examples: golang.org/x/text, github.com/stretchr/testify
      MODULE_PATH = %r{[a-zA-Z0-9\-_.~]+(?:/[a-zA-Z0-9\-_.~]+)+}

      # Go versions follow semver with a "v" prefix: v1.2.3, v0.0.0-20210101-abcdef123456
      GO_VERSION = /v?#{Version::VERSION_PATTERN}/

      # Full additional_dependency string: module/path@vX.Y.Z
      GO_DEP_WITH_VERSION =
        /\A\s*(?<name>#{MODULE_PATH})\s*@\s*(?<version>#{GO_VERSION})\s*\z/x

      # Module path without version
      GO_DEP_WITHOUT_VERSION =
        /\A\s*(?<name>#{MODULE_PATH})\s*\z/x

      # Parses a single Go module dependency string (e.g. "golang.org/x/text@v0.3.0")
      # into a structured hash. Returns nil if the string cannot be parsed
      # or has no version.
      #
      # The returned hash follows the same interface as
      # Dependabot::Python::RequirementParser.parse:
      #   { name:, normalised_name:, version:, requirement:, extras:, language:, registry: }
      sig { params(dependency_string: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def self.parse(dependency_string)
        match = dependency_string.strip.match(GO_DEP_WITH_VERSION)
        return nil unless match

        name = T.must(match[:name])
        raw_version = T.must(match[:version])

        # Strip leading "v" for the stored version but keep it for the requirement
        version = raw_version.sub(/\Av/, "")
        return nil unless Version.correct?(version)

        {
          name: name,
          normalised_name: normalise_name(name),
          version: version,
          requirement: raw_version,
          extras: nil,
          language: "golang",
          registry: nil
        }
      end

      # Go module names are already normalised (lowercase paths).
      # We simply downcase to ensure consistency.
      sig { params(name: String).returns(String) }
      def self.normalise_name(name)
        name.downcase
      end

      private_class_method :normalise_name
    end
  end
end

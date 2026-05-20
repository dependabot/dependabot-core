# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/go_modules/version"

module Dependabot
  module GoModules
    class RequirementParser
      extend T::Sig

      MODULE_PATH = %r{[a-zA-Z0-9\-_.~]+(?:/[a-zA-Z0-9\-_.~]+)+}

      GO_VERSION = /v?#{Version::VERSION_PATTERN}/

      GO_DEP_WITH_VERSION =
        /\A\s*(?<name>#{MODULE_PATH})\s*@\s*(?<version>#{GO_VERSION})\s*\z/x

      GO_DEP_WITHOUT_VERSION =
        /\A\s*(?<name>#{MODULE_PATH})\s*\z/x

      sig { params(dependency_string: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def self.parse(dependency_string)
        match = dependency_string.strip.match(GO_DEP_WITH_VERSION)
        return nil unless match

        name = T.must(match[:name])
        raw_version = T.must(match[:version])

        version = raw_version.delete_prefix("v")
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

      sig { params(name: String).returns(String) }
      def self.normalise_name(name)
        name.downcase
      end

      private_class_method :normalise_name
    end
  end
end

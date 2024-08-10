# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/bundler/file_fetcher"
require "dependabot/bundler/file_parser"
require "dependabot/bundler/update_checker"
require "dependabot/bundler/file_updater"
require "dependabot/bundler/metadata_finder"
require "dependabot/bundler/requirement"
require "dependabot/bundler/version"

require "dependabot/pull_request_creator/labeler"

module Dependabot
  module Bundler
    PACKAGE_MANAGER = "bundler"
    SUPPORTED_BUNDLER_VERSIONS = T.let(["2"].freeze, T::Array[String])
    UNSUPPORTED_BUNDLER_VERSIONS = T.let([].freeze, T::Array[String])
    DEPRECATED_BUNDLER_VERSIONS = T.let(["1"].freeze, T::Array[String])

    class PackageManager < PackageManagerBase
      extend T::Sig
      include Helpers

      sig { params(version: String).void }
      def initialize(version)
        @version = T.let(version, String)
        @name = T.let(PACKAGE_MANAGER, String)
        @deprecated_versions = T.let(DEPRECATED_BUNDLER_VERSIONS, T::Array[String])
        @unsupported_versions = T.let(UNSUPPORTED_BUNDLER_VERSIONS, T::Array[String])
        @supported_versions = T.let(SUPPORTED_BUNDLER_VERSIONS, T::Array[String])
      end

      sig { override.returns(String) }
      attr_reader :name

      sig { override.returns(String) }
      attr_reader :version

      sig { override.returns(T::Array[String]) }
      attr_reader :deprecated_versions

      sig { override.returns(T::Array[String]) }
      attr_reader :unsupported_versions

      sig { override.returns(T::Array[String]) }
      attr_reader :supported_versions
    end
  end
end

Dependabot::PullRequestCreator::Labeler
  .register_label_details(Dependabot::Bundler::PACKAGE_MANAGER, name: "ruby", colour: "ce2d2d")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  Dependabot::Bundler::PACKAGE_MANAGER,
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("runtime")
    return true if groups.include?("default")

    groups.any? { |g| g.include?("prod") }
  end
)

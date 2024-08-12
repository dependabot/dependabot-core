# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Bundler
    PACKAGE_MANAGER = "bundler"
    SUPPORTED_BUNDLER_VERSIONS = T.let(["2"].freeze, T::Array[String])
    DEPRECATED_BUNDLER_VERSIONS = T.let(["1"].freeze, T::Array[String])

    class PackageManager < PackageManagerBase
      extend T::Sig
      include Helpers

      sig { params(version: String).void }
      def initialize(version)
        @version = T.let(version, String)
        @name = T.let(PACKAGE_MANAGER, String)
        @deprecated_versions = T.let(DEPRECATED_BUNDLER_VERSIONS, T::Array[String])

        @supported_versions = T.let(SUPPORTED_BUNDLER_VERSIONS, T::Array[String])
      end

      sig { override.returns(String) }
      attr_reader :name

      sig { override.returns(String) }
      attr_reader :version

      sig { override.returns(T.nilable(T::Array[String])) }
      attr_reader :deprecated_versions

      sig { override.returns(T::Array[String]) }
      attr_reader :supported_versions

      sig { override.returns(T::Boolean) }
      def deprecated
        deprecated_versions&.include?(version) || false
      end

      sig { override.returns(T::Boolean) }
      def unsupported
        Gem::Version.new(version) < Gem::Version.new("2.0.0")
      end
    end
  end
end

# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Vcpkg
    class Version < Dependabot::Version
      extend T::Sig

      VERSION_PATTERN = /\A([0-9]+(?:\.[0-9]+)*(?:-[0-9A-Za-z\-\.]+)?(?:\+[0-9A-Za-z\-\.]+)?)(?:\#([0-9]+))?\z/

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        parsed_version = parse_version(@version_string)
        super(T.cast(parsed_version[:base_version], String))
        @port_version = T.let(parsed_version[:port_version], T.nilable(Integer))
      end

      sig { returns(T.nilable(Integer)) }
      attr_reader :port_version

      sig { override.returns(String) }
      def to_s
        port_version ? "#{super}##{port_version}" : super
      end

      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        case other
        when Version
          # Compare with another vcpkg version
          base_comparison = super
          return base_comparison if base_comparison.nil? || !base_comparison.zero?

          # If base versions are equal, compare port versions
          (port_version || 0) <=> (other.port_version || 0)
        when String
          # Compare with a string by creating a version object from it
          begin
            self <=> self.class.new(other)
          rescue ArgumentError
            # If the string isn't a valid version, try comparing as base version only
            super(Gem::Version.new(other))
          end
        when Gem::Version, Dependabot::Version
          # Compare with a regular Gem::Version by comparing just the base version
          super
        end
      end

      private

      sig { params(version_string: String).returns(T::Hash[Symbol, T.untyped]) }
      def parse_version(version_string)
        match = version_string.match(VERSION_PATTERN)
        raise ArgumentError, "Malformed version number string #{version_string}" unless match

        {
          base_version: match[1],
          port_version: match[2]&.to_i
        }
      end
    end
  end
end

Dependabot::Utils.register_version_class("vcpkg", Dependabot::Vcpkg::Version)

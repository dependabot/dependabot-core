# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/docker_compose/version"
require "dependabot/ecosystem"
require "dependabot/docker_compose/requirement"

module Dependabot
  module DockerCompose
    ECOSYSTEM = "docker_compose"

    SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class DockerPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "docker_compose"

      # As docker_compose updater is an in house custom utility, We use a placeholder
      # version number for docker_compose updater
      VERSION = "1.0.0"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        void
      end
      def initialize
        super(
          name: NAME,
          version: Version.new(VERSION),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end

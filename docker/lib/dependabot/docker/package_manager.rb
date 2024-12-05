# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/docker/version"
require "dependabot/ecosystem"
require "dependabot/docker/requirement"

module Dependabot
  module Docker
    ECOSYSTEM = T.let("docker", String)
    PACKAGE_MANAGER = T.let("docker", String)

    MANIFEST_FILE = T.let("Dockerfile", String)

    FILE_TYPE = "file"
    API_VERSION_KEY = "apiVersion"
    RESOURCE_KEY = "kind"
    REGISTERY_KEY = "registry"
    IMAGE_KEY = "image"
    REPOSITORY_KEY = "repository"
    TAG_KEY = "tag"
    VERSION_KEY = "version"
    DIGEST_KEY = "digest"

    REGISTERY_DOMAIN = "docker.io"

    YAML_REGEXP = /^[^\.].*\.ya?ml$/i
    DOCKER_REGEXP = /dockerfile/i
    FROM_REGEX = /FROM(\s+--platform\=\S+)?/i

    SHA256_KEY = "sha256"

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          PACKAGE_MANAGER,
          Version.new(raw_version),
          [],
          [],
          requirement,
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

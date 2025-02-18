# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/shared/shared_file_parser"
require "dependabot/docker_compose/package_manager"

module Dependabot
  module DockerCompose
    class FileParser < Dependabot::Shared::SharedFileParser
      extend T::Sig

      FROM_IMAGE = %r{^(?:#{REGISTRY}/)?#{IMAGE}(?:#{TAG})?(?:#{DIGEST})?(?:#{NAME})?}

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: DockerPackageManager.new
          ),
          T.nilable(Ecosystem)
        )
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        composefiles.each do |composefile|
          yaml = YAML.safe_load(T.must(composefile.content))
          yaml["services"].each do |_, service|
            parsed_from_image = T.must(FROM_IMAGE.match(service["image"])).named_captures
            parsed_from_image["registry"] = nil if parsed_from_image["registry"] == "docker.io"

            version = version_from(parsed_from_image)
            next unless version

            dependency_set << build_dependency(composefile, parsed_from_image, version)
          end
        end

        dependency_set.dependencies
      end

      private

      sig { override.returns(String) }
      def package_manager
        "docker_compose"
      end

      sig { override.returns(String) }
      def file_type
        "docker-compose.yml"
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def composefiles
        dependency_files
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No #{file_type}!"
      end
    end
  end
end

Dependabot::FileParsers.register(
  "docker_compose",
  Dependabot::DockerCompose::FileParser
)

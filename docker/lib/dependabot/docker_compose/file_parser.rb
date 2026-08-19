# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/shared/shared_file_parser"
require "dependabot/docker_compose/package_manager"

module Dependabot
  module DockerCompose
    class FileParser < Dependabot::Shared::SharedFileParser
      extend T::Sig

      ENV_VAR = /\${(?<variable_name>[^}:]+)(?:\:-(?<default_value>[^}]+))?}/
      DIGEST = /(?<digest>[0-9a-f]{64})/
      IMAGE_REGEX = %r{^(#{REGISTRY}/)?#{IMAGE}#{TAG}?(?:@sha256:#{DIGEST})?#{NAME}?}x

      FROM = /FROM/i
      PLATFORM = /--platform\=(?<platform>\S+)/

      FROM_LINE =
        %r{^#{FROM}\s+(#{PLATFORM}\s+)?(#{REGISTRY}/)?
          #{IMAGE}#{TAG}?(?:@sha256:#{DIGEST})?#{NAME}?}x

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
          yaml = YAML.safe_load(T.must(composefile.content), permitted_classes: [Symbol], aliases: true)
          next unless yaml.is_a?(Hash)
          next unless yaml["services"].is_a?(Hash)

          yaml["services"].each do |_, service|
            next unless service.is_a?(Hash)

            parsed_from_image = parse_image_spec(service)
            next unless parsed_from_image

            parsed_from_image["registry"] = nil if parsed_from_image["registry"] == "docker.io"

            version = version_from(parsed_from_image)
            next unless version

            dependency_set << build_dependency(composefile, parsed_from_image, version)
          end
        end

        dependency_set.dependencies
      end

      private

      sig { params(service: T::Hash[String, Object]).returns(T.nilable(T::Hash[String, T.nilable(String)])) }
      def parse_image_spec(service)
        image = service["image"]
        return service_image(image) if image.is_a?(String)

        build = service["build"]
        if build.is_a?(Hash)
          dockerfile_inline = build["dockerfile_inline"]
          return nil unless dockerfile_inline.is_a?(String)
          return nil if dockerfile_inline.match?(/^FROM\s+\${[^}]+}$/)

          match = FROM_LINE.match(dockerfile_inline)
          return match&.named_captures
        end

        nil
      end

      sig { params(image: String).returns(T.nilable(T::Hash[String, T.nilable(String)])) }
      def service_image(image)
        docker_image = image

        if image.match?(/^#{ENV_VAR}/o)
          default_value = ENV_VAR.match(image)&.named_captures&.fetch("default_value")
          return unless default_value

          docker_image = default_value
        end

        IMAGE_REGEX.match(docker_image)&.named_captures
      end

      sig { params(parsed_image: T::Hash[String, T.nilable(String)]).returns(T.nilable(String)) }
      def version_from(parsed_image)
        return nil if parsed_image["tag"]&.match?(ENV_VAR)

        super
      end

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

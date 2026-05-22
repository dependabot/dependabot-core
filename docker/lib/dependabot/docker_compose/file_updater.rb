# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"

module Dependabot
  module DockerCompose
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      extend T::Sig
      extend T::Helpers

      YAML_REGEXP = /(docker-)?compose(?>\.[\w-]+)?\.ya?ml/i
      IMAGE_REGEX = /(?:from|image:\s*)/i

      sig { override.returns(String) }
      def file_type
        "Docker compose"
      end

      sig { override.returns(Regexp) }
      def yaml_file_pattern
        YAML_REGEXP
      end

      sig { override.returns(Regexp) }
      def container_image_regex
        IMAGE_REGEX
      end

      sig { override.params(escaped_declaration: String).returns(Regexp) }
      def build_old_declaration_regex(escaped_declaration)
        %r{#{IMAGE_REGEX}\s+["']?(?:\$\{[^\}:]+:-)?(docker\.io/)?#{escaped_declaration}(?:\})?["']?(?=\s|$)}
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []
        dependency_files.each do |file|
          next unless requirement_changed?(file, T.must(dependency))

          updated_files << updated_file(
            file: file,
            content: updated_compose_content(file)
          )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      # Compose files can express image references in two distinct ways:
      #
      #   1. As an embedded Dockerfile via the `build.dockerfile_inline` key, where image
      #      references appear as `FROM <image>:<tag>` inside a YAML block scalar. These are
      #      matched by the dockerfile-style declaration regex.
      #   2. As a compose `image:` value, either inline (`image: nginx:1`) or as a folded/
      #      literal YAML block scalar that wraps onto the next line. These are matched by
      #      the YAML image replacement helper.
      #
      # We try the dockerfile-style replacement first to cover `dockerfile_inline` blocks,
      # and fall back to the YAML image replacement when no `FROM` declaration matched so
      # the `image:` form (including folded/literal scalars) is still handled.
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_compose_content(file)
        dockerfile_content = build_updated_dockerfile_content(file)
        return dockerfile_content if dockerfile_content != file.content

        yaml_content = build_updated_yaml_content(file)
        raise "Expected content to change!" if yaml_content == file.content

        yaml_content
      end
    end
  end
end

Dependabot::FileUpdaters.register(
  "docker_compose",
  Dependabot::DockerCompose::FileUpdater
)

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
            content: T.must(updated_dockerfile_content(file))
          )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end
    end
  end
end

Dependabot::FileUpdaters.register(
  "docker_compose",
  Dependabot::DockerCompose::FileUpdater
)

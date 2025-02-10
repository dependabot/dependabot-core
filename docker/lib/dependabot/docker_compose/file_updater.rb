# typed: strict
# frozen_string_literal: true

require_relative "../common/base_file_updater"

module Dependabot
  module DockerCompose
    class FileUpdater < Dependabot::DockerCommon::BaseFileUpdater
      extend T::Sig

      IMAGE_REGEX = /image:\s*/

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/(docker-)?compose(?>\.[\w-]+)?\.ya?ml/i]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, T.must(dependency))

          updated_files <<
            updated_file(
              file: file,
              content: updated_dockercompose_file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.returns(String) }
      def file_type
        "docker-compose.yml"
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_dockercompose_file_content(file)
        updated_content = update_content(file)
        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def update_content(file)
        old_source = T.must(previous_sources(file)).first
        new_source = T.must(sources(file)).first

        content = file.content
        old_declaration = build_declaration(old_source)
        new_declaration = build_declaration(new_source)

        escaped_declaration = Regexp.escape(old_declaration)
        image_regex = %r{^\s*#{IMAGE_REGEX}\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)}

        content.gsub(image_regex) do |old_dec|
          old_dec.gsub(old_declaration, new_declaration)
        end
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(String) }
      def build_declaration(source)
        declaration = ""
        declaration += "#{source[:registry]}/" if source[:registry]
        declaration += T.must(dependency).name
        declaration += ":#{source[:tag]}" if source[:tag]
        declaration += "@sha256:#{source[:digest]}" if source[:digest]
        declaration
      end
    end
  end
end

Dependabot::FileUpdaters.register(
  "docker_compose",
  Dependabot::DockerCompose::FileUpdater
)

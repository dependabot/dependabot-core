# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"

module Dependabot
  module DockerCompose
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      extend T::Sig
      extend T::Helpers

      YAML_REGEXP = /(docker-)?compose(?>\.[\w-]+)?\.ya?ml/i
      IMAGE_REGEX = /image:\s*/

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [YAML_REGEXP]
      end

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
        %r{#{IMAGE_REGEX}\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)}
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []
        dependency_files.each do |file|
          next unless requirement_changed?(file, T.must(dependency))

          updated_files << updated_file(
            file: file,
            content: updated_dockerfile_content(file)
          )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      sig do
        override.params(previous_content: String, old_source: T::Hash[Symbol, T.nilable(String)],
                        new_source: T::Hash[Symbol, T.nilable(String)]).returns(String)
      end
      def update_digest_and_tag(previous_content, old_source, new_source)
        old_digest = old_source[:digest]
        new_digest = new_source[:digest]

        old_tag = old_source[:tag]
        new_tag = new_source[:tag]

        old_declaration =
          if private_registry_url(old_source)
            "#{private_registry_url(old_source)}/"
          else
            ""
          end
        old_declaration += T.must(dependency).name
        old_declaration +=
          if specified_with_tag?(old_source)
            ":#{old_tag}"
          else
            ""
          end
        old_declaration +=
          if old_digest&.start_with?("sha256:")
            "@#{old_digest}"
          else
            ""
          end

        escaped_declaration = Regexp.escape(old_declaration)

        old_declaration_regex = build_old_declaration_regex(escaped_declaration)

        previous_content.gsub(old_declaration_regex) do |old_dec|
          old_dec
            .gsub(":#{old_tag}", ":#{new_tag}")
            .gsub(old_digest.to_s, new_digest.to_s)
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register(
  "docker_compose",
  Dependabot::DockerCompose::FileUpdater
)

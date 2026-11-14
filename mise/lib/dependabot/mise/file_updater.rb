# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/helpers"

module Dependabot
  module Mise
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig
      include Dependabot::Mise::Helpers

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        # Get all unique files that need updates from dependency requirements
        files_to_update = dependencies.flat_map do |dep|
          dep.requirements.map(&:file)
        end.uniq

        # Update only the files that contain dependencies being updated
        files_to_update.each do |file_name|
          mise_file = dependency_files.find { |f| f.name == file_name }
          next unless mise_file

          new_content = updated_mise_toml_content(mise_file.content.to_s, mise_file.name)
          updated_files << updated_file(file: mise_file, content: new_content) if new_content != mise_file.content
        end

        updated_files
      end

      private

      sig { params(content: String, file_name: String).returns(String) }
      def updated_mise_toml_content(content, file_name)
        # Only update dependencies that have requirements in this specific file
        deps_for_file = dependencies.select do |dep|
          dep.requirements.any? { |r| r.file == file_name }
        end

        deps_for_file.each_with_object(content.dup) do |dep, updated_content|
          next if requested_version_for(dep, file_name) == new_version_string_for(dep, file_name)

          new_content = update_dependency(updated_content, dep, file_name)
          if new_content == updated_content
            raise no_files_changed_error(
              "Expected content to change for #{dep.name} in #{file_name}!",
              dependency_name: dep.name,
              dependency_file: file_name
            )
          end

          updated_content.replace(new_content)
        end
      end

      sig { params(content: String, dep: Dependabot::Dependency, file_name: String).returns(String) }
      def update_dependency(content, dep, file_name)
        tool = Regexp.escape(dep.name)
        tool_key = "(?:\"#{tool}\"|'#{tool}'|#{tool})"
        old_version = Regexp.escape(requested_version_for(dep, file_name))
        new_version = new_version_string_for(dep, file_name)

        # Handles plain keys:   erlang = "27.3.2"
        # Handles quoted keys:  "npm:@redocly/cli" = "2.19.1"
        content = content.gsub(
          /^([ \t]*#{tool_key}[ \t]*=[ \t]*)(["'])#{old_version}\2/,
          "\\1\\2#{new_version}\\2"
        )

        # Handles inline table: python = { version = "3.11.0", virtualenv = ".venv" }
        content = content.gsub(
          /^([ \t]*#{tool_key}[ \t]*=[ \t]*\{.*?version[ \t]*=[ \t]*)(["'])#{old_version}\2/,
          "\\1\\2#{new_version}\\2"
        )

        # Handles table header: [tools.golang]
        #                       version = "1.18"
        # Stop at the next table header, allowing array values before the version.
        content.gsub(
          /(
            ^[ \t]*\[tools\.#{tool_key}\]
            (?:(?!^[ \t]*\[).)*?
            ^[ \t]*version[ \t]*=[ \t]*
          )(["'])#{old_version}\2/mx,
          "\\1\\2#{new_version}\\2"
        )
      end

      sig { params(dep: Dependabot::Dependency, file_name: String).returns(String) }
      def requested_version_for(dep, file_name)
        # Get the requirement from the specific file being updated
        requirement = T.must(dep.previous_requirements)
                       .find { |r| r.file == file_name }

        requirement&.requirement_string || dep.previous_version.to_s
      end

      sig { params(dep: Dependabot::Dependency, file_name: String).returns(String) }
      def new_version_string_for(dep, file_name)
        # Get the new requirement for the specific file
        requirement = dep.requirements.find { |r| r.file == file_name }

        requirement&.requirement_string || dep.version.to_s
      end

      sig { override.void }
      def check_required_files
        mise_files = dependency_files.select { |f| Dependabot::Mise::FileFetcher.mise_config_file?(f.name) }
        return unless mise_files.empty?

        raise "No mise configuration file found!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("mise", Dependabot::Mise::FileUpdater)

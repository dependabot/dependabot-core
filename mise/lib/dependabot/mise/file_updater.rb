# typed: strong
# frozen_string_literal: true

require "toml-rb"

require "dependabot/errors"
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

      # Accept a text replacement only if it updates the parsed tool version.
      sig { params(content: String, dep: Dependabot::Dependency, file_name: String).returns(String) }
      def update_dependency(content, dep, file_name)
        old_version = requested_version_for(dep, file_name)
        new_version = new_version_string_for(dep, file_name)
        # An already-updated tool could otherwise validate an unrelated edit.
        return content unless declared_version(content, dep.name) == old_version

        offset = 0
        while (index = content.index(old_version, offset))
          candidate = content.dup
          candidate[index, old_version.length] = new_version
          return candidate if candidate_version(candidate, dep.name) == new_version

          offset = index + 1
        end

        content
      rescue TomlRB::Error => e
        raise Dependabot::DependencyFileNotParseable.new(file_name, e.message)
      end

      # Version arrays and arrays of tables are not managed, so they return nil.
      sig { params(content: String, tool: String).returns(T.nilable(String)) }
      def declared_version(content, tool)
        tools = T.cast(TomlRB.parse(content), T::Hash[String, Object])["tools"]
        return unless tools.is_a?(Hash)

        value = T.let(tools[tool], Object)
        value = T.let(value["version"], Object) if value.is_a?(Hash)
        value if value.is_a?(String)
      end

      # Invalid candidates are skipped; invalid original manifests still raise.
      sig { params(content: String, tool: String).returns(T.nilable(String)) }
      def candidate_version(content, tool)
        declared_version(content, tool)
      rescue TomlRB::Error
        nil
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

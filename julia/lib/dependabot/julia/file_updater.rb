# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "tempfile"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/julia/registry_client"

module Dependabot
  module Julia
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/(?:Julia)?Project\.toml$/i, /(?:Julia)?Manifest(?:-v[\d.]+)?\.toml$/i]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        # Use DependabotHelper.jl for manifest updating
        if project_file
          project_path = T.let(nil, T.nilable(String))

          begin
            project_path = write_temp_project_file

            result = registry_client.update_manifest(
              project_path: project_path,
              updates: build_updates_hash
            )

            if result["error"]
              # Fallback to Ruby TOML manipulation
              Dependabot.logger.warn(
                "DependabotHelper.jl update failed: #{result['error']}, " \
                "falling back to Ruby updating"
              )
              return fallback_updated_dependency_files
            end

            # Create updated files from DependabotHelper.jl results
            updated_files = build_updated_files_from_result(result)
          rescue StandardError => e
            # Fallback to Ruby TOML manipulation if Julia helper fails
            Dependabot.logger.warn(
              "DependabotHelper.jl update failed with exception: #{e.message}, " \
              "falling back to Ruby updating"
            )
            return fallback_updated_dependency_files
          ensure
            File.delete(project_path) if project_path && File.exist?(project_path)
          end
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      # Fallback method using Ruby TOML manipulation
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fallback_updated_dependency_files
        updated_files = []

        # Update Project.toml file
        if project_file && file_changed?(T.must(project_file))
          updated_files << updated_file(
            file: T.must(project_file),
            content: updated_project_content
          )
        end

        # Update Manifest.toml file if it exists and dependencies have changed
        if manifest_file
          updated_manifest_content = build_updated_manifest_content
          if updated_manifest_content != T.must(manifest_file).content
            updated_files << updated_file(
              file: T.must(manifest_file),
              content: updated_manifest_content
            )
          end
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      private

      sig { returns(T::Hash[String, String]) }
      def build_updates_hash
        updates = {}
        dependencies.each do |dependency|
          next unless dependency.version

          updates[dependency.name] = dependency.version
        end
        updates
      end

      sig { params(result: T::Hash[String, T.untyped]).returns(T::Array[Dependabot::DependencyFile]) }
      def build_updated_files_from_result(result)
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        if result["project_content"] && result["project_content"] != T.must(project_file).content
          updated_files << updated_file(
            file: T.must(project_file),
            content: result["project_content"]
          )
        end

        if manifest_file && result["manifest_content"] &&
           result["manifest_content"] != T.must(manifest_file).content
          updated_files << updated_file(
            file: T.must(manifest_file),
            content: result["manifest_content"]
          )
        end

        updated_files
      end

      # Helper methods for DependabotHelper.jl integration

      sig { returns(Dependabot::Julia::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          Dependabot::Julia::RegistryClient.new(
            credentials: credentials
          ),
          T.nilable(Dependabot::Julia::RegistryClient)
        )
      end

      sig { returns(String) }
      def write_temp_project_file
        temp_file = Tempfile.new(["Project", ".toml"])
        temp_file.write(T.must(project_file).content)
        temp_file.close
        T.must(temp_file.path)
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.empty?

        return if dependency_files.any? { |f| f.name.match?(/^(Julia)?Project\.toml$/i) }

        raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found."
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        @project_file ||= T.let(
          dependency_files.find do |f|
            f.name.match?(/^(Julia)?Project\.toml$/i)
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_file
        @manifest_file ||= T.let(
          dependency_files.find do |f|
            f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(String) }
      def updated_project_content
        return T.must(T.must(project_file).content) unless project_file

        content = T.must(T.must(project_file).content)

        dependencies.each do |dependency|
          # Find the new requirement for this dependency
          new_requirement = dependency.requirements
                                      .find { |req| T.cast(req[:file], String) == T.must(project_file).name }
                                      &.fetch(:requirement)

          next unless new_requirement

          content = update_dependency_requirement_in_content(content, dependency.name, new_requirement)
        end

        content
      end

      sig { params(content: String, dependency_name: String, new_requirement: String).returns(String) }
      def update_dependency_requirement_in_content(content, dependency_name, new_requirement)
        # Pattern to match the dependency in [compat] section
        # Handles various quote styles and spacing
        pattern = /(^\s*#{Regexp.escape(dependency_name)}\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s#\n]+)(\s*(?:\#.*)?$)/mx

        if content.match?(pattern)
          # Replace existing entry
          content.gsub(pattern, "\\1\"#{new_requirement}\"\\2")
        else
          # Add new entry to [compat] section
          add_compat_entry_to_content(content, dependency_name, new_requirement)
        end
      end

      sig { params(content: String, dependency_name: String, requirement: String).returns(String) }
      def add_compat_entry_to_content(content, dependency_name, requirement)
        # Find [compat] section or create it
        if content.match?(/^\s*\[compat\]\s*$/m)
          # Add to existing [compat] section
          content.gsub(/(\[compat\]\s*\n)/, "\\1#{dependency_name} = \"#{requirement}\"\n")
        else
          # Add new [compat] section at the end
          content + "\n[compat]\n#{dependency_name} = \"#{requirement}\"\n"
        end
      end

      sig { returns(String) }
      def build_updated_manifest_content
        return T.must(T.must(manifest_file).content) unless manifest_file

        content = T.must(T.must(manifest_file).content)

        dependencies.each do |dependency|
          next unless dependency.version

          content = update_dependency_version_in_manifest(content, dependency.name, T.must(dependency.version))
        end

        content
      end

      sig { params(content: String, dependency_name: String, new_version: String).returns(String) }
      def update_dependency_version_in_manifest(content, dependency_name, new_version)
        # Pattern to find the dependency entry and update its version
        # Matches the [[deps.DependencyName]] section and updates the version line within it
        dep_start = /^\[\[deps\.#{Regexp.escape(dependency_name)}\]\]\s*\n(?:.*\n)*?/
        version_key = /^\s*version\s*=\s*/
        old_version = /(?:"[^"]*"|'[^']*'|[^\s#\n]+)/
        trailing = /\s*(?:\#.*)?$/
        pattern = /(#{dep_start})(#{version_key})#{old_version}(#{trailing})/mx

        if content.match?(pattern)
          content.gsub(pattern, "\\1\\2\"#{new_version}\"\\3")
        else
          # If pattern doesn't match, fall back to original approach
          Dependabot.logger.warn("Could not find manifest entry for #{dependency_name}, using fallback")
          fallback_update_manifest_content(content, dependency_name, new_version)
        end
      end

      sig { params(content: String, dependency_name: String, new_version: String).returns(String) }
      def fallback_update_manifest_content(content, dependency_name, new_version)
        # Fallback to parse-and-dump for complex cases
        parsed_manifest = T.cast(TomlRB.parse(content), T::Hash[String, T.untyped])

        deps_section = T.cast(parsed_manifest["deps"] || {}, T::Hash[String, T.untyped])
        if deps_section[dependency_name]
          dep_entries = deps_section[dependency_name]
          update_dependency_entries(dep_entries, new_version)
        end

        T.cast(TomlRB.dump(parsed_manifest), String)
      end

      sig { params(dependency: Dependabot::Dependency, manifest: T::Hash[String, T.untyped]).void }
      def update_dependency_in_manifest(dependency, manifest)
        deps_section = T.cast(manifest["deps"] || {}, T::Hash[String, T.untyped])
        return unless deps_section[dependency.name]

        dep_entries = deps_section[dependency.name]
        update_dependency_entries(dep_entries, dependency.version)
      end

      sig { params(dep_entries: T.untyped, version: T.nilable(String)).void }
      def update_dependency_entries(dep_entries, version)
        if dep_entries.is_a?(Array)
          dep_entries.each do |dep_entry|
            dep_entry["version"] = version if dep_entry.is_a?(Hash) && dep_entry["uuid"]
          end
        elsif dep_entries.is_a?(Hash) && dep_entries["uuid"]
          dep_entries["version"] = version
        end
      end
    end
  end
end

Dependabot::FileUpdaters.register("julia", Dependabot::Julia::FileUpdater)

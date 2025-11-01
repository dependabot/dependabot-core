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

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/(?:Julia)?Project\.toml$/i, /(?:Julia)?Manifest(?:-v[\d.]+)?\.toml$/i]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        # If no manifest file, just update Project.toml using Ruby
        return fallback_updated_dependency_files unless project_file && manifest_file

        # Use DependabotHelper.jl for manifest updating
        updated_files_with_julia_helper
      rescue StandardError => e
        # Fallback to Ruby TOML manipulation if Julia helper fails
        Dependabot.logger.warn(
          "DependabotHelper.jl update failed with exception: #{e.message}, " \
          "falling back to Ruby updating"
        )
        fallback_updated_dependency_files
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_files_with_julia_helper
        updated_files = []
        project_dir = T.let(nil, T.nilable(String))

        begin
          # First, update the Project.toml using Ruby (handles compat section correctly)
          updated_project = updated_project_content

          # Write both files to a temporary directory
          project_dir = write_temp_project_directory(updated_project)

          # Now call Julia helper to update the Manifest.toml based on the updated Project.toml
          result = registry_client.update_manifest(
            project_path: project_dir,
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

          # Build updated files: use Ruby-updated Project.toml and Julia-updated Manifest.toml
          updated_files << updated_file(
            file: T.must(project_file),
            content: updated_project
          )

          # Include manifest update if Julia helper provided one. The
          # `manifest_path` from the Julia helper handles workspace cases
          # (for example "../Manifest.toml"). Build a DependencyFile for the
          # manifest whether or not it was originally fetched.
          if result["manifest_content"] && result["manifest_path"]
            manifest_path = result["manifest_path"]

            chosen_manifest_file = manifest_file_for_path(manifest_path)

            updated_files << updated_file(
              file: chosen_manifest_file,
              content: result["manifest_content"]
            )
          end
        ensure
          FileUtils.rm_rf(project_dir) if project_dir && File.exist?(project_dir)
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

      sig { params(project_content: String).returns(String) }
      def write_temp_project_directory(project_content)
        temp_dir = Dir.mktmpdir("dependabot-julia-")

        # Write the updated project file using the original filename
        File.write(File.join(temp_dir, T.must(project_file).name), project_content)

        # Write the existing manifest file using the original filename
        File.write(File.join(temp_dir, T.must(manifest_file).name), T.must(manifest_file).content) if manifest_file

        temp_dir
      end

      sig { params(manifest_path: String).returns(Dependabot::DependencyFile) }
      def manifest_file_for_path(manifest_path)
        # If we originally fetched a manifest and its name matches the path
        # returned by the Julia helper, use that file object so metadata
        # (like directory) is preserved. Otherwise create a lightweight
        # DependencyFile pointing at the correct relative path.
        if manifest_file && T.must(manifest_file).name == manifest_path
          T.must(manifest_file)
        else
          Dependabot::DependencyFile.new(
            name: manifest_path,
            content: "",
            directory: T.must(project_file).directory
          )
        end
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
        # Extract the [compat] section to update it specifically
        compat_section_match = content.match(/^\[compat\]\s*\n((?:(?!\[)[^\n]*\n)*?)(?=^\[|\z)/m)

        if compat_section_match
          compat_section = T.must(compat_section_match[1])
          # Pattern to match the dependency in the compat section
          pattern = /^(\s*#{Regexp.escape(dependency_name)}\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s#\n]+)(\s*(?:\#.*)?)$/

          if compat_section.match?(pattern)
            # Replace existing entry in compat section
            updated_compat = compat_section.gsub(pattern, "\\1\"#{new_requirement}\"\\2")
            content.sub(T.must(compat_section_match[0]), "[compat]\n#{updated_compat}")
          else
            # Add new entry to existing [compat] section
            add_compat_entry_to_content(content, dependency_name, new_requirement)
          end
        else
          # Add new [compat] section
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
          # If pattern doesn't match, use TOML parsing as fallback
          Dependabot.logger.warn("Could not find manifest entry for #{dependency_name}, using fallback")
          parsed_manifest = T.cast(TomlRB.parse(content), T::Hash[String, T.untyped])

          deps_section = T.cast(parsed_manifest["deps"] || {}, T::Hash[String, T.untyped])
          if deps_section[dependency_name]
            dep_entries = deps_section[dependency_name]
            update_dependency_entries(dep_entries, new_version)
          end

          T.cast(TomlRB.dump(parsed_manifest), String)
        end
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

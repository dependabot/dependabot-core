# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "tempfile"
require "fileutils"
require "pathname"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/julia/registry_client"
require "dependabot/notices"

module Dependabot
  module Julia
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/(?:Julia)?Project\.toml$/i, /(?:Julia)?Manifest(?:-v[\d.]+)?\.toml$/i]
      end

      sig { returns(T::Array[Dependabot::Notice]) }
      attr_reader :notices

      sig do
        override.params(
          dependencies: T::Array[Dependabot::Dependency],
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(dependencies:, dependency_files:, credentials:, repo_contents_path: nil, options: {})
        super
        @notices = T.let([], T::Array[Dependabot::Notice])
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        # If no project file, cannot proceed
        raise "No Project.toml file found" unless project_file

        # Use DependabotHelper.jl for manifest updating
        # This works for both standard packages and workspace packages
        updated_files_with_julia_helper
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def updated_files_with_julia_helper
        updated_files = []

        SharedHelpers.in_a_temporary_repo_directory(T.must(dependency_files.first).directory, repo_contents_path) do
          # First, update the Project.toml using Ruby (handles compat section correctly)
          updated_project = updated_project_content

          # Write the updated Project.toml
          File.write(T.must(project_file).name, updated_project)

          # Identify which manifest file to update (may be in parent directory for workspaces)
          # The Julia helper will tell us which file it updated via the manifest_path result
          actual_manifest = find_manifest_file

          # Only try to update manifest if one exists
          if actual_manifest.nil?
            # No manifest file - just return updated Project.toml
            return [updated_file(
              file: T.must(project_file),
              content: updated_project
            )]
          end

          # Now call Julia helper to update the Manifest.toml based on the updated Project.toml
          result = registry_client.update_manifest(
            project_path: Dir.pwd,
            updates: build_updates_hash
          )

          # Check if Julia helper returned an error
          if result["error"]
            error_message = result["error"]
            manifest_path = actual_manifest.name

            # Check if this is a Pkg resolver error (version conflicts or incompatible constraints)
            if error_message.start_with?("Pkg resolver error:")
              # Add a notice that will be shown in the PR
              @notices << Dependabot::Notice.new(
                mode: Dependabot::Notice::NoticeMode::WARN,
                type: "julia_manifest_not_updated",
                package_manager_name: "Pkg",
                title: "Could not update manifest #{manifest_path}",
                description: "The Julia package manager failed to update the new dependency versions " \
                             "in `#{manifest_path}`:\n\n```\n#{error_message}\n```",
                show_in_pr: true,
                show_alert: true
              )

              # Return only the updated Project.toml
              return [updated_file(
                file: T.must(project_file),
                content: updated_project
              )]
            else
              # For other errors, raise
              raise error_message
            end
          end

          # Build updated files: use Ruby-updated Project.toml and Julia-updated Manifest.toml
          updated_files << updated_file(
            file: T.must(project_file),
            content: updated_project
          )

          # Include manifest update if Julia helper provided one
          # Use the manifest we identified earlier - Julia helper has updated it
          if result["manifest_content"]
            updated_manifest_content = result["manifest_content"]
            if updated_manifest_content != actual_manifest.content
              updated_files << updated_file(
                file: actual_manifest,
                content: updated_manifest_content
              )
            end
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

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def find_manifest_file
        # The file fetcher has already identified the correct manifest file
        # For regular packages: manifest in same directory
        # For workspace packages: manifest in parent directory
        # We just need to find it in dependency_files
        project_dir = T.must(project_file).directory

        dependency_files.find do |f|
          f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i) &&
            (f.directory == project_dir || project_dir.start_with?(f.directory))
        end
      end

      sig { params(manifest_path: String).returns(Dependabot::DependencyFile) }
      def manifest_file_for_path(manifest_path)
        # manifest_path is relative to the project directory (e.g., "Manifest.toml" or "../Manifest.toml")
        # We need to resolve it to find the actual manifest file in dependency_files

        # Build the absolute path relative to the project directory
        project_dir = T.must(project_file).directory
        resolved_manifest_path = File.expand_path(manifest_path, project_dir)

        # Normalize by removing leading "/" to get repo-relative path
        resolved_manifest_path = resolved_manifest_path.sub(%r{^/}, "")

        # Find the matching manifest file in dependency_files
        found_manifest = dependency_files.find do |f|
          f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i) &&
            File.join(f.directory.sub(%r{^/}, ""), f.name) == resolved_manifest_path
        end

        # Return the found manifest if available, preserving its metadata
        return found_manifest if found_manifest

        # Otherwise create a new DependencyFile
        # Extract directory and name from the resolved path
        manifest_dir = File.dirname(resolved_manifest_path)
        manifest_name = File.basename(manifest_path)

        Dependabot::DependencyFile.new(
          name: manifest_name,
          content: "",
          directory: manifest_dir == "." ? "/" : "/#{manifest_dir}"
        )
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
          begin
            # Find manifest files in the same directory as the project file
            # For workspace packages, this may return nil if the manifest is in a parent directory
            # In that case, the Julia helper will handle finding the correct manifest later
            return nil unless project_file

            project_dir = T.must(project_file).directory

            dependency_files.find do |f|
              next unless f.name.match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)
              # Check if manifest is in the same directory as Project.toml
              f.directory == project_dir
            end
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

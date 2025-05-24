# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Julia
    class FileUpdater < Dependabot::FileUpdaters::Base
      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /Project\.toml$/i,
          /JuliaProject\.toml$/i,
          /Manifest(?:-v[\d.]+)?\.toml$/i
        ]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        # Update the project file
        updated_project_content = updated_project_content(project_file)
        if updated_project_content != project_file.content
          updated_files << updated_file(
            file: project_file,
            content: updated_project_content
          )
        end

        # Update the manifest file (if present)
        if manifest_file
          updated_manifest_content = updated_manifest_content_using_helper
          if updated_manifest_content != manifest_file.content
            updated_files << updated_file(
              file: manifest_file,
              content: updated_manifest_content
            )
          end
        end

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        # Ensure a Project.toml or JuliaProject.toml file is present.
        return if dependency_files.any? { |f| f.name.match?(/^(Julia)?Project\.toml$/i) }

        raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found."
      end

      sig { params(manifest: Dependabot::DependencyFile).returns(String) }
      def updated_manifest_content_using_helper(manifest)
        SharedHelpers.in_a_temporary_directory do
          write_temporary_dependency_files

          dependencies.each do |dep|
            SharedHelpers.run_shell_command(
              "julia --project=. -e 'import Pkg; Pkg.update(\"#{dep.name}\")'",
              allow_unsafe_shell_command: true
            )
          end

          # Get a hash of dependency names to updates that should be made
          deps_to_update = dependencies.map do |dependency|
            {
              "dependency_name" => dependency.name,
              "version" => dependency.version,
              "previous_version" => dependency.previous_version,
              "requirements" => dependency.requirements
            }
          end.to_json

          SharedHelpers.run_helper_subprocess(
            command: "julia --project=#{File.dirname(project_file.name)} #{julia_helper_path}",
            function: "update_manifest",
            args: {
              "project_path" => project_file.name,
              "manifest_path" => manifest_file.name,
              "deps_to_update" => deps_to_update
            }
          )
        end
      end

      sig { void }
      def write_dependency_files
        dependency_files.each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, file.content)
        end

        # Write project file with updated dependency requirements
        File.write(project_file.name, updated_project_content(project_file))
      end

      sig { returns(String) }
      def julia_helper_path
        File.join(
          File.dirname(__dir__), "../../../helpers/run_dependabot_helper.jl"
        )
      end

      sig { params(file: DependencyFile).returns(String) }
      def updated_manifest_content(file)
        # Initialize with a mutable type to avoid issues in blocks
        content = T.let(file.content, T.untyped)

        # Parse the manifest TOML
        toml = TomlRB.parse(content)
        # Make necessary updates
        dependencies.each do |dependency|
          update_manifest_for_dependency(toml, dependency)
        end

        # Convert back to TOML
        content = TomlRB.dump(toml)

        content
      end

      sig { params(file: DependencyFile).returns(String) }
      def updated_project_content(file)
        # Parse the project TOML
        toml = TomlRB.parse(file.content)
        # Make necessary updates
        dependencies.each do |dependency|
          update_project_for_dependency(toml, dependency)
        end

        # Convert back to TOML
        TomlRB.dump(toml)
      end

      sig { params(toml: T::Hash[String, T.untyped], dependency: Dependabot::Dependency).void }
      def update_project_for_dependency(toml, dependency)
        # Update dependency version requirements
        # Ensure 'deps' and 'compat' sections exist and contain the dependency
        return unless toml["deps"].is_a?(Hash) && toml["deps"][dependency.name]
        return unless toml["compat"].is_a?(Hash) && toml["compat"][dependency.name]

        # Find the requirement for the current project file
        req = dependency.requirements.find { |r| r[:file] == project_file.name && r[:requirement] }
        return unless req

        toml["compat"][dependency.name] = req[:requirement]
      end

      sig { params(toml: T::Hash[String, T.untyped], dependency: Dependabot::Dependency).void }
      def update_manifest_for_dependency(toml, dependency)
        # Manifest.toml lists dependencies as an array of tables: [[PackageName]]
        # TomlRB parses this into `toml["PackageName"]` being an array of hashes.
        dep_stanza_array = toml[dependency.name]
        return unless dep_stanza_array.is_a?(Array)

        # Iterate over each stanza for the dependency. Usually, there's one.
        # If multiple stanzas exist (e.g., due to different versions for different targets,
        # though less common in Julia's Manifest.toml for a single package name),
        # this will update the version in all of them.
        # A more robust approach might involve matching by UUID if available and unique.
        dep_stanza_array.each do |stanza|
          next unless stanza.is_a?(Hash) && stanza.key?("version")
          # TODO: If UUID is available on `dependency` object and in stanza, use it for a more precise match.
          # For now, if we find the package name and it has a version, update it.
          stanza["version"] = dependency.version
        end
      end

      sig { returns(DependencyFile) }
      def project_file
        file = dependency_files.find { |f| f.name.match?(/Project\.toml$/i) } ||
               dependency_files.find { |f| f.name.match?(/JuliaProject\.toml$/i) }

        file || raise("No Project.toml or JuliaProject.toml file found")
      end

      sig { returns(T.nilable(DependencyFile)) }
      def manifest_file
        dependency_files.find { |f| f.name.match?(/Manifest(?:-v[\d.]+)?\.toml$/i) }
      end
    end
  end
end

Dependabot::FileUpdaters.register("julia", Dependabot::Julia::FileUpdater)

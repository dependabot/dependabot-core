# typed: strict
# frozen_string_literal: true

require "tempfile"
require "fileutils"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/julia/version"
require "dependabot/julia/requirement"
require "dependabot/julia/registry_client"
require "dependabot/julia/package_manager"
require "dependabot/julia/language"
require "dependabot/ecosystem"

module Dependabot
  module Julia
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          source: Dependabot::Source,
          repo_contents_path: T.nilable(String),
          credentials: T::Array[Dependabot::Credential],
          reject_external_code: T::Boolean,
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        dependency_files:,
        source:,
        repo_contents_path: nil,
        credentials: [],
        reject_external_code: false,
        options: {}
      )
        super
        @registry_client = T.let(nil, T.nilable(Dependabot::Julia::RegistryClient))
        @custom_registries = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = T.let([], T::Array[Dependabot::Dependency])

        dependency_set += project_file_dependencies
        dependency_set.uniq
      end

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: PackageManager::ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new,
          T.nilable(Ecosystem::VersionManager)
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def language
        @language ||= T.let(
          Language.new(PackageManager::CURRENT_VERSION),
          T.nilable(Ecosystem::VersionManager)
        )
      end

      # Helper methods for DependabotHelper.jl integration

      sig { returns(Dependabot::Julia::RegistryClient) }
      def registry_client
        @registry_client ||= Dependabot::Julia::RegistryClient.new(
          credentials: credentials,
          custom_registries: custom_registries
        )
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def custom_registries
        @custom_registries ||= begin
          registries_config = T.cast(options[:registries], T.nilable(T::Hash[Symbol, T.anything]))
          registries = T.cast(registries_config&.dig(:julia), T.nilable(T::Array[T::Hash[Symbol, T.anything]])) || []
          # Convert string keys to symbols if needed
          registries.map do |registry|
            registry.transform_keys(&:to_sym)
          end
        end
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def project_file_dependencies
        dependencies_map = T.let({}, T::Hash[String, Dependabot::Dependency])

        # Parse all project files in the workspace
        all_project_files.each do |proj_file|
          parse_single_project_file(proj_file, dependencies_map)
        end

        apply_manifest_versions(dependencies_map)

        dependencies_map.values
      end

      # Resolve the installed version of each dependency from the manifest
      # (Julia's lockfile), matching by UUID.
      sig { params(dependencies_map: T::Hash[String, Dependabot::Dependency]).void }
      def apply_manifest_versions(dependencies_map)
        versions = manifest_versions_by_uuid
        return if versions.empty?

        dependencies_map.transform_values! do |dep|
          uuid = T.cast(dep.metadata[:julia_uuid], T.nilable(String))
          version = uuid && versions[uuid]
          next dep unless version

          Dependabot::Dependency.new(
            name: dep.name,
            version: version,
            requirements: dep.requirements,
            package_manager: "julia",
            metadata: dep.metadata
          )
        end
      end

      sig { returns(T::Hash[String, String]) }
      def manifest_versions_by_uuid
        manifest = manifest_file
        return {} unless manifest

        result = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        Dir.mktmpdir("julia_manifest") do |temp_dir|
          # Written under a fixed name: version-suffixed manifests
          # (Manifest-v1.11.toml) would otherwise be skipped by Pkg when the
          # helper's Julia version doesn't match.
          manifest_path = File.join(temp_dir, "Manifest.toml")
          File.write(manifest_path, manifest.content)
          result = registry_client.parse_manifest(manifest_path)
        end
        result = T.must(result)

        if result["error"]
          Dependabot.logger.warn("Failed to parse Julia manifest: #{result['error']}")
          return {}
        end

        deps = T.cast(result["dependencies"] || [], T::Array[T.untyped])
        deps.each_with_object({}) do |dep_info, map|
          dep_hash = T.cast(dep_info, T::Hash[String, T.untyped])
          uuid = T.cast(dep_hash["uuid"], T.nilable(String))
          version = T.cast(dep_hash["version"], T.nilable(String)).to_s
          next if uuid.nil? || version.empty?

          map[uuid] = version
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_file
        dependency_files.find do |f|
          File.basename(f.name).match?(/^(Julia)?Manifest(?:-v[\d.]+)?\.toml$/i)
        end
      end

      sig { params(proj_file: Dependabot::DependencyFile, dependencies_map: T::Hash[String, Dependabot::Dependency]).void }
      def parse_single_project_file(proj_file, dependencies_map)
        temp_dir = Dir.mktmpdir("julia_project")
        # File names like "../Project.toml" (a workspace root fetched from a
        # member directory) must not escape the temp dir; fall back to the
        # basename since each project file gets its own directory anyway.
        project_path = File.expand_path(File.join(temp_dir, proj_file.name))
        unless project_path.start_with?("#{File.expand_path(temp_dir)}#{File::SEPARATOR}")
          project_path = File.join(temp_dir, File.basename(proj_file.name))
        end
        FileUtils.mkdir_p(File.dirname(project_path))
        File.write(project_path, proj_file.content)

        begin
          result = registry_client.parse_project(project_path: project_path)

          return if result["error"]

          # Process dependencies
          parsed_deps = T.cast(result["dependencies"] || [], T::Array[T.untyped])
          merge_dependencies_from_list(parsed_deps, ["deps"], proj_file.name, dependencies_map)

          # Process weak dependencies
          parsed_weak_deps = T.cast(result["weak_dependencies"] || [], T::Array[T.untyped])
          merge_dependencies_from_list(parsed_weak_deps, ["weakdeps"], proj_file.name, dependencies_map)
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      sig do
        params(
          dep_list: T::Array[T.untyped],
          groups: T::Array[String],
          file_name: String,
          dependencies_map: T::Hash[String, Dependabot::Dependency]
        ).void
      end
      def merge_dependencies_from_list(dep_list, groups, file_name, dependencies_map)
        dep_list.each do |dep_info|
          dep_hash = T.cast(dep_info, T::Hash[String, T.untyped])
          name = T.cast(dep_hash["name"], String)
          next if name == "julia" # Skip Julia version requirement

          uuid = T.cast(dep_hash["uuid"], T.nilable(String))
          requirement_string = T.cast(dep_hash["requirement"], T.nilable(String))

          new_requirement = {
            requirement: requirement_string,
            file: file_name,
            groups: groups,
            source: nil
          }

          if dependencies_map.key?(name)
            # Merge requirements from additional project files
            existing_dep = T.must(dependencies_map[name])

            # UUID is a package's identity in Julia: two same-named entries
            # with different UUIDs are different packages, and merging them
            # would run updates against the wrong UUID.
            existing_uuid = T.cast(existing_dep.metadata[:julia_uuid], T.nilable(String))
            if uuid && existing_uuid && uuid != existing_uuid
              Dependabot.logger.warn(
                "Skipping #{name} in #{file_name}: UUID #{uuid} conflicts with #{existing_uuid} " \
                "from another project file"
              )
              next
            end

            existing_requirements = existing_dep.requirements + [new_requirement]
            dependencies_map[name] = Dependabot::Dependency.new(
              name: name,
              version: nil,
              requirements: existing_requirements,
              package_manager: "julia",
              metadata: existing_dep.metadata
            )
          else
            # Create new dependency
            dependencies_map[name] = Dependabot::Dependency.new(
              name: name,
              version: nil,
              requirements: [new_requirement],
              package_manager: "julia",
              metadata: uuid ? { julia_uuid: uuid } : {}
            )
          end
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def all_project_files
        dependency_files.select { |f| f.name.match?(/Project\.toml$/i) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        @project_file ||= T.let(
          all_project_files.first || get_original_file("Project.toml") || get_original_file("JuliaProject.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { override.void }
      def check_required_files
        raise "No Project.toml or JuliaProject.toml!" if all_project_files.empty?
      end
    end
  end
end

Dependabot::FileParsers.register("julia", Dependabot::Julia::FileParser)

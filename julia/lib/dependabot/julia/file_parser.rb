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
          registries = options.dig(:registries, :julia) || []
          # Convert string keys to symbols if needed
          registries.map do |registry|
            registry.is_a?(Hash) ? registry.transform_keys(&:to_sym) : registry
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

        dependencies_map.values
      end

      sig { params(proj_file: Dependabot::DependencyFile, dependencies_map: T::Hash[String, Dependabot::Dependency]).void }
      def parse_single_project_file(proj_file, dependencies_map)
        temp_dir = Dir.mktmpdir("julia_project")
        project_path = File.join(temp_dir, proj_file.name)
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
            existing_requirements = existing_dep.requirements.dup
            existing_requirements << new_requirement
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

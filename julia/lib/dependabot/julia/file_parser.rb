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
        @temp_dir = T.let(nil, T.nilable(String))
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

      sig { returns(String) }
      def write_temp_project_file
        @temp_dir ||= Dir.mktmpdir("julia_project")
        project_path = File.join(@temp_dir, T.must(project_file).name)
        File.write(project_path, T.must(project_file).content)
        project_path
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def project_file_dependencies
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        return dependencies unless project_file

        # Use DependabotHelper.jl for project parsing
        project_path = write_temp_project_file

        begin
          result = registry_client.parse_project(project_path: project_path)

          raise Dependabot::DependencyFileNotParseable, result["error"] if result["error"]

          # Convert DependabotHelper.jl result to Dependabot::Dependency objects
          dependencies = build_dependencies_from_julia_result(result)
        ensure
          # Cleanup temporary directory
          FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
        end

        dependencies
      end

      sig { params(result: T::Hash[String, T.untyped]).returns(T::Array[Dependabot::Dependency]) }
      def build_dependencies_from_julia_result(result)
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        # Process dependencies and weak dependencies (matching CompatHelper.jl behavior)
        # Note: We don't process dev_dependencies/extras to match CompatHelper.jl
        parsed_deps = T.cast(result["dependencies"] || [], T::Array[T.untyped])
        dependencies.concat(build_dependencies_from_dep_list(parsed_deps, ["deps"]))

        parsed_weak_deps = T.cast(result["weak_dependencies"] || [], T::Array[T.untyped])
        dependencies.concat(build_dependencies_from_dep_list(parsed_weak_deps, ["weakdeps"]))

        dependencies
      end

      sig do
        params(
          dep_list: T::Array[T.untyped],
          groups: T::Array[String]
        ).returns(T::Array[Dependabot::Dependency])
      end
      def build_dependencies_from_dep_list(dep_list, groups)
        dep_list.filter_map do |dep_info|
          dep_hash = T.cast(dep_info, T::Hash[String, T.untyped])
          name = T.cast(dep_hash["name"], String)
          next if name == "julia" # Skip Julia version requirement

          uuid = T.cast(dep_hash["uuid"], T.nilable(String))
          # NOTE: Missing "requirement" means no compat entry (any version acceptable)
          requirement_string = T.cast(dep_hash["requirement"], T.nilable(String))

          Dependabot::Dependency.new(
            name: name,
            version: nil, # Julia dependencies don't use locked versions
            requirements: [{
              requirement: requirement_string,
              file: T.must(project_file).name,
              groups: groups,
              source: nil
            }],
            package_manager: "julia",
            metadata: uuid ? { julia_uuid: uuid } : {}
          )
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        @project_file ||= T.let(
          get_original_file("Project.toml") || get_original_file("JuliaProject.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { override.void }
      def check_required_files
        raise "No Project.toml or JuliaProject.toml!" unless project_file
      end
    end
  end
end

Dependabot::FileParsers.register("julia", Dependabot::Julia::FileParser)

# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "tempfile"
require "fileutils"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/julia/version"
require "dependabot/julia/requirement"
require "dependabot/julia/registry_client"

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
        @parsed_project_file = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        @parsed_manifest_file = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
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

      private

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
        project_path = File.join(@temp_dir, "Project.toml")
        File.write(project_path, T.must(project_file).content)
        project_path
      end

      sig { returns(T.nilable(String)) }
      def write_temp_manifest_file
        return nil unless manifest_file

        @temp_dir ||= Dir.mktmpdir("julia_project")
        manifest_path = File.join(@temp_dir, "Manifest.toml")
        File.write(manifest_path, T.must(manifest_file).content)
        manifest_path
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def project_file_dependencies
        dependencies = T.let([], T::Array[Dependabot::Dependency])
        return dependencies unless project_file

        # Use DependabotHelper.jl for project parsing
        project_path = write_temp_project_file
        manifest_path = write_temp_manifest_file if manifest_file

        begin
          result = registry_client.parse_project(
            project_path: project_path,
            manifest_path: manifest_path
          )

          if result["error"]
            # Fallback to Ruby TOML parsing if Julia helper fails
            Dependabot.logger.warn(
              "DependabotHelper.jl parsing failed: #{result['error']}, " \
              "falling back to Ruby parsing"
            )
            return fallback_project_file_dependencies
          end

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
        parsed_deps = T.cast(result["dependencies"] || [], T::Array[T.untyped])

        parsed_deps.each do |dep_info|
          dep_hash = T.cast(dep_info, T::Hash[String, T.untyped])
          name = T.cast(dep_hash["name"], String)
          uuid = T.cast(dep_hash["uuid"], T.nilable(String))
          requirement_string = T.cast(dep_hash["requirement"] || "*", String)
          resolved_version = T.cast(dep_hash["resolved_version"], T.nilable(String))

          # Skip Julia version requirement
          next if name == "julia"

          dependencies << Dependabot::Dependency.new(
            name: name,
            version: resolved_version,
            requirements: [{
              requirement: requirement_string,
              file: T.must(project_file).name,
              groups: ["runtime"],
              source: nil
            }],
            package_manager: "julia",
            metadata: uuid ? { julia_uuid: uuid } : {}
          )
        end

        dependencies
      end

      # Fallback method using Ruby TOML parsing
      sig { returns(T::Array[Dependabot::Dependency]) }
      def fallback_project_file_dependencies
        dependencies = T.let([], T::Array[Dependabot::Dependency])

        parsed_project = parsed_project_file
        deps_section = T.cast(parsed_project["deps"] || {}, T::Hash[String, T.untyped])
        compat_section = T.cast(parsed_project["compat"] || {}, T::Hash[String, T.untyped])

        deps_section.each do |name, _uuid|
          next if name == "julia" # Skip Julia version requirement

          # Get the version requirement from compat section, default to "*" if not specified
          requirement_string = T.cast(compat_section[name] || "*", String)

          # Get the exact version from Manifest.toml if available
          exact_version = version_from_manifest(name)

          dependencies << Dependabot::Dependency.new(
            name: name,
            version: exact_version,
            requirements: [{
              requirement: requirement_string,
              file: T.must(project_file).name,
              groups: ["runtime"],
              source: nil
            }],
            package_manager: "julia"
          )
        end

        dependencies
      end

      sig { params(dependency_name: String).returns(T.nilable(String)) }
      def version_from_manifest(dependency_name)
        return nil unless manifest_file

        # Try using DependabotHelper.jl first
        temp_dir = Dir.mktmpdir("julia_manifest_only")
        manifest_path = File.join(temp_dir, "Manifest.toml")
        File.write(manifest_path, T.must(manifest_file).content)

        begin
          # We need the UUID for the DependabotHelper.jl call, so fallback to Ruby parsing
          # Note: Future enhancement could add name-only lookup to DependabotHelper.jl
          fallback_version_from_manifest(dependency_name)
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      sig { params(dependency_name: String).returns(T.nilable(String)) }
      def fallback_version_from_manifest(dependency_name)
        return nil unless manifest_file

        parsed_manifest = parsed_manifest_file

        # Look for the dependency in the manifest
        deps_section = T.cast(parsed_manifest["deps"], T.nilable(T::Hash[String, T.untyped]))
        if deps_section && deps_section[dependency_name]
          # Manifest v2 format
          dep_entries = deps_section[dependency_name]
          if dep_entries.is_a?(Array) && dep_entries.first.is_a?(Hash)
            return T.cast(dep_entries.first["version"], T.nilable(String))
          end
        end

        nil
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        @project_file ||= T.let(
          get_original_file("Project.toml") || get_original_file("JuliaProject.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_file
        @manifest_file ||= T.let(
          get_original_file("Manifest.toml") || get_original_file("JuliaManifest.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_project_file
        return @parsed_project_file if @parsed_project_file

        parsed_content = T.cast(TomlRB.parse(T.must(project_file).content), T::Hash[String, T.untyped])
        @parsed_project_file = parsed_content
        parsed_content
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError => e
        raise Dependabot::DependencyFileNotParseable, "Error parsing #{T.must(project_file).name}: #{e.message}"
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_manifest_file
        return {} unless manifest_file
        return @parsed_manifest_file if @parsed_manifest_file

        parsed_content = T.cast(TomlRB.parse(T.must(manifest_file).content), T::Hash[String, T.untyped])
        @parsed_manifest_file = parsed_content
        parsed_content
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError => e
        raise Dependabot::DependencyFileNotParseable, "Error parsing #{T.must(manifest_file).name}: #{e.message}"
      end

      sig { override.void }
      def check_required_files
        raise "No Project.toml or JuliaProject.toml!" unless project_file
      end
    end
  end
end

Dependabot::FileParsers.register("julia", Dependabot::Julia::FileParser)

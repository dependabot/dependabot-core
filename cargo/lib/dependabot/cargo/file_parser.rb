# typed: true
# frozen_string_literal: true

require "toml-rb"
require "pathname"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/cargo/requirement"
require "dependabot/cargo/version"
require "dependabot/errors"
require "dependabot/cargo/registry_fetcher"
require "dependabot/cargo/language"
require "dependabot/cargo/package_manager"

# Relevant Cargo docs can be found at:
# - https://doc.rust-lang.org/cargo/reference/manifest.html
# - https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html
module Dependabot
  module Cargo
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      DEPENDENCY_TYPES =
        %w(dependencies dev-dependencies build-dependencies).freeze

      def parse
        check_rust_workspace_root

        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies if lockfile

        dependencies = dependency_set.dependencies

        # TODO: Handle patched dependencies
        dependencies.reject! { |d| patched_dependencies.include?(d.name) }

        # TODO: Currently, Dependabot can't handle dependencies that have
        # multiple sources. Fix that!
        dependencies.reject do |dep|
          dep.requirements.map { |r| r.fetch(:source) }.uniq.count > 1
        end
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(begin
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          )
        end, T.nilable(Dependabot::Ecosystem))
      end

      private

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(cargo_version)),
          T.nilable(Dependabot::Cargo::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(begin
          Language.new(T.must(rust_version))
        end, T.nilable(Dependabot::Cargo::Language))
      end

      sig { returns(T.nilable(String)) }
      def rust_version
        @rust_version ||= T.let(begin
          version = SharedHelpers.run_shell_command("rustc --version")
          version.match(/rustc\s*(\d+\.\d+(.\d+)*)/)&.captures&.first
        end, T.nilable(String))
      end

      sig { returns(T.nilable(String)) }
      def cargo_version
        @cargo_version ||= T.let(begin
          version = SharedHelpers.run_shell_command("cargo --version")
          version.match(/cargo\s*(\d+\.\d+(.\d+)*)/)&.captures&.first
        end, T.nilable(String))
      end

      def check_rust_workspace_root
        cargo_toml = dependency_files.find { |f| f.name == "Cargo.toml" }
        workspace_root = parsed_file(cargo_toml).dig("package", "workspace")
        return unless workspace_root

        msg = "This project is part of a Rust workspace but is not the " \
              "workspace root." \

        if cargo_toml&.directory != "/"
          msg += "Please update your settings so Dependabot points at the " \
                 "workspace root instead of #{cargo_toml&.directory}."
        end
        raise Dependabot::DependencyFileNotEvaluatable, msg
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def manifest_dependencies
        dependency_set = DependencySet.new

        manifest_files.each do |file|
          DEPENDENCY_TYPES.each do |type|
            parsed_file(file).fetch(type, {}).each do |name, requirement|
              next unless name == name_from_declaration(name, requirement)
              next if lockfile && !version_from_lockfile(name, requirement)

              dependency_set << build_dependency(name, requirement, type, file)
            end

            parsed_file(file).fetch("target", {}).each do |_, t_details|
              t_details.fetch(type, {}).each do |name, requirement|
                next unless name == name_from_declaration(name, requirement)
                next if lockfile && !version_from_lockfile(name, requirement)

                dependency_set <<
                  build_dependency(name, requirement, type, file)
              end
            end
          end

          workspace = parsed_file(file).fetch("workspace", {})
          workspace.fetch("dependencies", {}).each do |name, requirement|
            next unless name == name_from_declaration(name, requirement)
            next if lockfile && !version_from_lockfile(name, requirement)

            dependency_set <<
              build_dependency(name, requirement, "workspace.dependencies", file)
          end
        end

        dependency_set
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def build_dependency(name, requirement, type, file)
        Dependency.new(
          name: name,
          version: version_from_lockfile(name, requirement),
          package_manager: "cargo",
          requirements: [{
            requirement: requirement_from_declaration(requirement),
            file: file.name,
            groups: [type],
            source: source_from_declaration(requirement)
          }]
        )
      end

      def lockfile_dependencies
        dependency_set = DependencySet.new
        return dependency_set unless lockfile

        parsed_file(lockfile).fetch("package", []).each do |package_details|
          next unless package_details["source"]

          # TODO: This isn't quite right, as it will only give us one
          # version of each dependency (when in fact there are many)
          dependency_set << Dependency.new(
            name: package_details["name"],
            version: version_from_lockfile_details(package_details),
            package_manager: "cargo",
            requirements: []
          )
        end

        dependency_set
      end

      def patched_dependencies
        root_manifest = manifest_files.find { |f| f.name == "Cargo.toml" }
        return [] unless parsed_file(root_manifest)["patch"]

        parsed_file(root_manifest)["patch"].values.flat_map(&:keys)
      end

      def requirement_from_declaration(declaration)
        if declaration.is_a?(String)
          return declaration == "" ? nil : declaration
        end
        raise "Unexpected dependency declaration: #{declaration}" unless declaration.is_a?(Hash)
        return declaration["version"] if declaration["version"].is_a?(String) && declaration["version"] != ""

        nil
      end

      def name_from_declaration(name, declaration)
        return name if declaration.is_a?(String)
        raise "Unexpected dependency declaration: #{declaration}" unless declaration.is_a?(Hash)

        declaration.fetch("package", name)
      end

      def source_from_declaration(declaration)
        return if declaration.is_a?(String)
        raise "Unexpected dependency declaration: #{declaration}" unless declaration.is_a?(Hash)

        return git_source_details(declaration) if declaration["git"]
        return { type: "path" } if declaration["path"]

        registry_source_details(declaration)
      end

      def registry_source_details(declaration)
        registry_name = declaration["registry"]
        return if registry_name.nil?

        index_url = cargo_config_field("registries.#{registry_name}.index")
        if index_url.nil?
          raise "Registry index for #{registry_name} must be defined via " \
                "cargo config"
        end

        if index_url.start_with?("sparse+")
          sparse_registry_source_details(registry_name, index_url)
        else
          source = Source.from_url(index_url)
          registry_fetcher = RegistryFetcher.new(
            source: T.must(source),
            credentials: credentials
          )

          {
            type: "registry",
            name: registry_name,
            index: index_url,
            dl: registry_fetcher.dl,
            api: registry_fetcher.api
          }
        end
      end

      def sparse_registry_source_details(registry_name, index_url)
        token = credentials.find do |cred|
          cred["type"] == "cargo_registry" && cred["registry"] == registry_name
        end&.fetch("token", nil)
        # Fallback to configuration in the environment if available
        token ||= cargo_config_from_env("registries.#{registry_name}.token")

        headers = {}
        headers["Authorization"] = "Token #{token}" if token

        url = index_url.delete_prefix("sparse+")
        url << "/" unless url.end_with?("/")
        url << "config.json"
        config_json = JSON.parse(RegistryClient.get(url: url, headers: headers).body)

        {
          type: "registry",
          name: registry_name,
          index: index_url,
          dl: config_json["dl"],
          api: config_json["api"]
        }
      end

      # Looks up dotted key name in cargo config
      # e.g. "registries.my_registry.index"
      def cargo_config_field(key_name)
        cargo_config_from_env(key_name) || cargo_config_from_file(key_name)
      end

      def cargo_config_from_env(key_name)
        env_var = "CARGO_#{key_name.upcase.tr('-.', '_')}"
        ENV.fetch(env_var, nil)
      end

      def cargo_config_from_file(key_name)
        parsed_file(cargo_config).dig(*key_name.split("."))
      end

      def version_from_lockfile(name, declaration)
        return unless lockfile

        candidate_packages =
          parsed_file(lockfile).fetch("package", [])
                               .select { |p| p["name"] == name }

        if (req = requirement_from_declaration(declaration))
          req = Cargo::Requirement.new(req)

          candidate_packages =
            candidate_packages
            .select { |p| req.satisfied_by?(version_class.new(p["version"])) }
        end

        candidate_packages =
          candidate_packages
          .select do |p|
            git_req?(declaration) ^ !p["source"]&.start_with?("git+")
          end

        package =
          candidate_packages
          .max_by { |p| version_class.new(p["version"]) }

        return unless package

        version_from_lockfile_details(package)
      end

      def git_req?(declaration)
        source_from_declaration(declaration)&.fetch(:type, nil) == "git"
      end

      def git_source_details(declaration)
        {
          type: "git",
          url: declaration["git"],
          branch: declaration["branch"],
          ref: declaration["tag"] || declaration["rev"]
        }
      end

      def version_from_lockfile_details(package_details)
        return package_details["version"] unless package_details["source"]&.start_with?("git+")

        package_details["source"].split("#").last
      end

      def check_required_files
        raise "No Cargo.toml!" unless get_original_file("Cargo.toml")
      end

      def parsed_file(file)
        @parsed_file ||= {}
        @parsed_file[file.name] ||= TomlRB.parse(file.content)
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, file.path
      end

      def manifest_files
        @manifest_files ||=
          dependency_files
          .select { |f| f.name.end_with?("Cargo.toml") }
          .reject(&:support_file?)
      end

      def lockfile
        @lockfile ||= get_original_file("Cargo.lock")
      end

      def cargo_config
        @cargo_config ||= get_original_file(".cargo/config.toml")
      end

      def version_class
        Cargo::Version
      end
    end
  end
end

Dependabot::FileParsers.register("cargo", Dependabot::Cargo::FileParser)

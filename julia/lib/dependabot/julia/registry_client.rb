# Julia Registry Client with DependabotHelper.jl integration
# typed: strict
# frozen_string_literal: true

require "time"
require "dependabot/credential"
require "dependabot/julia/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Julia
    class RegistryClient
      extend T::Sig

      sig do
        params(credentials: T::Array[Dependabot::Credential], custom_registries: T::Array[T::Hash[Symbol, String]]).void
      end
      def initialize(credentials:, custom_registries: [])
        @credentials = credentials
        @custom_registries = custom_registries
      end

      sig { params(package_name: String, package_uuid: T.nilable(String)).returns(T.nilable(Gem::Version)) }
      def fetch_latest_version(package_name, package_uuid = nil)
        # Use custom registries if available
        return fetch_latest_version_with_custom_registries(package_name, package_uuid) if custom_registries.any?

        args = { package_name: package_name }
        args[:package_uuid] = package_uuid if package_uuid

        result = call_julia_helper(
          function: "get_latest_version",
          args: args
        )

        # Check if the result itself contains an error (package not found)
        return nil if result["error"]

        # Extract version from the result structure
        # The Julia helper returns version directly in the result
        return nil unless result["version"]

        Gem::Version.new(result["version"])
      rescue StandardError => e
        Dependabot.logger.warn(
          "Failed to fetch latest version for #{package_name}: #{e.message}"
        )
        nil
      end

      sig { params(package_name: String, package_uuid: T.nilable(String)).returns(T.nilable(Gem::Version)) }
      def fetch_latest_version_with_custom_registries(package_name, package_uuid = nil)
        args = {
          package_name: package_name,
          package_uuid: package_uuid || "",
          registry_urls: custom_registry_urls
        }

        result = call_julia_helper(
          function: "get_latest_version_with_custom_registries",
          args: args
        )

        # Check if the result itself contains an error (package not found)
        return nil if result["error"]

        # Extract version from the result structure
        return nil unless result["version"]

        Gem::Version.new(result["version"])
      rescue StandardError => e
        Dependabot.logger.warn(
          "Failed to fetch latest version with custom registries for #{package_name}: #{e.message}"
        )
        nil
      end

      sig { params(package_name: String, package_uuid: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def fetch_package_metadata(package_name, package_uuid)
        call_julia_helper(
          function: "get_package_metadata",
          args: { package_name: package_name, package_uuid: package_uuid }
        )
      rescue StandardError => e
        Dependabot.logger.warn("Failed to fetch metadata for #{package_name}: #{e.message}")
        nil
      end

      sig do
        params(
          project_path: String,
          package_name: String,
          target_version: String
        ).returns(T::Hash[String, T.untyped])
      end
      def check_update_compatibility(project_path, package_name, target_version)
        call_julia_helper(
          function: "check_update_compatibility",
          args: {
            project_path: project_path,
            package_name: package_name,
            target_version: target_version
          }
        )
      end

      sig do
        params(
          project_path: String,
          manifest_path: T.nilable(String)
        ).returns(T::Hash[String, T.untyped])
      end
      def parse_project(project_path:, manifest_path: nil)
        args = { project_path: project_path }
        args[:manifest_path] = manifest_path if manifest_path

        call_julia_helper(
          function: "parse_project",
          args: args
        )
      end

      sig { params(manifest_path: String).returns(T::Hash[String, T.untyped]) }
      def parse_manifest(manifest_path)
        call_julia_helper(
          function: "parse_manifest",
          args: { manifest_path: manifest_path }
        )
      end

      sig do
        params(
          manifest_path: String,
          name: String,
          uuid: String
        ).returns(T.nilable(String))
      end
      def get_version_from_manifest(manifest_path, name, uuid)
        result = call_julia_helper(
          function: "get_version_from_manifest",
          args: {
            manifest_path: manifest_path,
            name: name,
            uuid: uuid
          }
        )

        result["version"] unless result["error"]
      end

      sig { params(package_name: String, package_uuid: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
      def find_package_source_url(package_name, package_uuid = nil)
        args = { package_name: package_name }
        args[:package_uuid] = package_uuid if package_uuid

        call_julia_helper(
          function: "find_package_source_url",
          args: args
        )
      end

      sig do
        params(
          package_name: String,
          source_url: String
        ).returns(T::Hash[String, T.untyped])
      end
      def extract_package_metadata_from_url(package_name, source_url)
        call_julia_helper(
          function: "extract_package_metadata_from_url",
          args: {
            package_name: package_name,
            source_url: source_url
          }
        )
      end

      sig do
        params(
          project_path: String,
          updates: T::Hash[String, String]
        ).returns(T::Hash[String, T.untyped])
      end
      def update_manifest(project_path:, updates:)
        call_julia_helper(
          function: "update_manifest",
          args: {
            project_path: project_path,
            updates: updates
          }
        )
      end

      sig { params(package_name: String, version: String, package_uuid: T.nilable(String)).returns(T.nilable(Time)) }
      def fetch_version_release_date(package_name, version, package_uuid = nil)
        result = call_julia_helper(
          function: "get_version_release_date",
          args: {
            package_name: package_name,
            version: version,
            package_uuid: package_uuid
          }
        )

        # Check if the result contains an error
        return nil if result["error"]

        # Parse the release date if available
        return nil unless result["release_date"]

        Time.parse(result["release_date"])
      rescue StandardError => e
        Dependabot.logger.warn("Failed to fetch release date for #{package_name} v#{version}: #{e.message}")
        nil
      end

      sig { params(package_name: String, package_uuid: T.nilable(String)).returns(T::Array[String]) }
      def fetch_available_versions(package_name, package_uuid = nil)
        # Use custom registries if available
        return fetch_available_versions_with_custom_registries(package_name, package_uuid) if custom_registries.any?

        args = { package_name: package_name }
        args[:package_uuid] = package_uuid if package_uuid

        result = call_julia_helper(
          function: "get_available_versions",
          args: args
        )

        # Check if the result contains an error
        return [] if result["error"]

        # Extract versions array from the result
        versions = result["versions"]
        return [] unless versions.is_a?(Array)

        versions.map(&:to_s)
      rescue StandardError => e
        Dependabot.logger.warn("Failed to fetch available versions for #{package_name}: #{e.message}")
        []
      end

      sig { params(package_name: String, package_uuid: T.nilable(String)).returns(T::Array[String]) }
      def fetch_available_versions_with_custom_registries(package_name, package_uuid = nil)
        args = {
          package_name: package_name,
          package_uuid: package_uuid || "",
          registry_urls: custom_registry_urls
        }

        result = call_julia_helper(
          function: "get_available_versions_with_custom_registries",
          args: args
        )

        # Check if the result contains an error
        return [] if result["error"]

        # Extract versions array from the result
        versions = result["versions"]
        return [] unless versions.is_a?(Array)

        versions.map(&:to_s)
      rescue StandardError => e
        Dependabot.logger.warn(
          "Failed to fetch available versions with custom registries for #{package_name}: #{e.message}"
        )
        []
      end

      private

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      attr_reader :custom_registries

      sig { returns(T::Array[String]) }
      def custom_registry_urls
        custom_registries.filter_map { |reg| reg[:url] }
      end

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig do
        params(
          function: String,
          args: T::Hash[Symbol, T.untyped]
        ).returns(T::Hash[String, T.untyped])
      end
      def call_julia_helper(function:, args:)
        # Use the main julia helpers directory as project (contains Project.toml with DependabotHelper in [sources])
        julia_project_dir = File.dirname(julia_helper_script)
        julia_command = "julia --project=#{julia_project_dir} #{julia_helper_script}"

        SharedHelpers.run_helper_subprocess(
          command: julia_command,
          function: function,
          args: args,
          env: julia_env,
          allow_unsafe_shell_command: true
        )
      end

      sig { returns(String) }
      def julia_helper_script
        # Use environment variable if available, otherwise fall back to relative path
        helpers_path = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        if helpers_path
          File.join(helpers_path, "julia", "run_dependabot_helper.jl")
        else
          # Fallback for development/test environments
          File.join(__dir__, "..", "..", "..", "helpers", "run_dependabot_helper.jl")
        end
      end

      sig { returns(T::Hash[String, String]) }
      def julia_env
        env = {}

        if ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
          # In production/CI, use the shared depot where packages were precompiled
          user_depot = File.join(ENV.fetch("HOME", "/home/dependabot"), ".julia")
          # Trailing : is intentional. It automatically includes the bundled stdlibs
          env["JULIA_DEPOT_PATH"] = "#{user_depot}:"
        end
        # In development use the default Julia depot

        # Add Julia-specific environment variables for registry authentication
        julia_credentials = credentials.select { |c| c["type"] == "julia_registry" }
        julia_credentials.each_with_index do |cred, index|
          env["JULIA_PKG_SERVER_REGISTRY_PREFERENCE_#{index}"] = cred.fetch("url")
          env["JULIA_PKG_SERVER_#{index}_TOKEN"] = cred.fetch("token") if cred["token"]
        end

        env
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "excon"
require "time"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/registry_client"
require "dependabot/npm_and_yarn/package/registry_finder"
require "dependabot/npm_and_yarn/version"

module Dependabot
  module NpmAndYarn
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      # Lifecycle scripts that run automatically during package installation.
      # These are security-relevant because they execute with user privileges.
      # https://docs.npmjs.com/cli/v11/using-npm/scripts#npm-install
      INSTALL_SCRIPTS = T.let(
        %w(preinstall install postinstall prepublish preprepare prepare postprepare).freeze,
        T::Array[String]
      )

      sig { override.returns(T.nilable(String)) }
      def homepage_url
        # Attempt to use version_listing first, as fetching the entire listing
        # array can be slow (if it's large)
        return latest_version_listing["homepage"] if latest_version_listing["homepage"]

        listing = all_version_listings.find { |_, l| l["homepage"] }
        listing&.last&.fetch("homepage", nil) || super
      end

      sig { override.returns(T.nilable(String)) }
      def maintainer_changes
        return unless npm_releaser
        return unless npm_listing.dig("time", dependency.version)
        return if previous_releasers&.include?(npm_releaser)

        "This version was pushed to npm by " \
          "[#{npm_releaser}](https://www.npmjs.com/~#{npm_releaser}), a new " \
          "releaser for #{dependency.name} since your current version."
      end

      sig { override.returns(T.nilable(String)) }
      def install_script_changes
        return unless dependency.previous_version

        previous_scripts = install_scripts_for_version(dependency.previous_version)
        current_scripts = install_scripts_for_version(dependency.version)

        return if previous_scripts == current_scripts

        added = current_scripts.keys - previous_scripts.keys
        modified = (current_scripts.keys & previous_scripts.keys).reject do |script|
          current_scripts[script] == previous_scripts[script]
        end

        changes = []
        changes << format_script_list("adds", added) if added.any?
        changes << format_script_list("modifies", modified) if modified.any?

        return if changes.empty?

        total_scripts = added.size + modified.size
        verb = total_scripts == 1 ? "runs" : "run"

        "This version #{changes.join(' and ')} that #{verb} during installation. " \
          "Review the package contents before updating."
      end

      private

      sig { params(action: String, scripts: T::Array[String]).returns(String) }
      def format_script_list(action, scripts)
        script_names = scripts.map { |s| "`#{s}`" }.join(", ")
        noun = scripts.size == 1 ? "script" : "scripts"
        "#{action} #{script_names} #{noun}"
      end

      sig { params(version: T.nilable(String)).returns(T::Hash[String, String]) }
      def install_scripts_for_version(version)
        return {} unless version

        version_data = all_version_listings.find { |v, _| v == version }&.last
        return {} unless version_data

        scripts = version_data["scripts"] || {}
        scripts.slice(*INSTALL_SCRIPTS)
      end

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return find_source_from_registry if new_source.nil?

        source_type = new_source&.[](:type) || new_source&.fetch("type")

        case source_type
        when "git" then find_source_from_git_url
        when "registry" then find_source_from_registry
        else raise "Unexpected source type: #{source_type}"
        end
      end

      sig { returns(T.nilable(String)) }
      def npm_releaser
        all_version_listings
          .find { |v, _| v == dependency.version }
          &.last&.dig("_npmUser", "name")
      end

      sig { returns(T.nilable(T::Array[String])) }
      def previous_releasers
        times = npm_listing.fetch("time")

        cutoff =
          if dependency.previous_version && times[dependency.previous_version]
            Time.parse(times[dependency.previous_version])
          elsif times[dependency.version]
            Time.parse(times[dependency.version]) - 1
          end
        return unless cutoff

        all_version_listings
          .reject { |v, _| Time.parse(times[v]) > cutoff }
          .filter_map { |_, d| d.dig("_npmUser", "name") }
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_registry
        # Attempt to use version_listing first, as fetching the entire listing
        # array can be slow (if it's large)
        potential_sources =
          [
            get_source(latest_version_listing["repository"]),
            get_source(latest_version_listing["homepage"]),
            get_source(latest_version_listing["bugs"])
          ].compact

        return potential_sources.first if potential_sources.any?

        potential_sources =
          all_version_listings.flat_map do |_, listing|
            [
              get_source(listing["repository"]),
              get_source(listing["homepage"]),
              get_source(listing["bugs"])
            ]
          end.compact

        potential_sources.first
      end

      sig { returns(T.nilable(T::Hash[T.any(String, Symbol), T.untyped])) }
      def new_source
        sources = dependency.requirements
                            .map { |r| r.fetch(:source) }.uniq.compact
                            .sort_by { |source| Package::RegistryFinder.central_registry?(source[:url]) ? 1 : 0 }

        sources.first
      end

      sig do
        params(
          details: T.nilable(T.any(String, T::Array[T.untyped], T::Hash[String, T.untyped]))
        )
          .returns(T.nilable(Dependabot::Source))
      end
      def get_source(details)
        potential_url = get_url(details)
        return unless potential_url

        potential_source = Source.from_url(potential_url)
        return unless potential_source

        potential_source.directory = get_directory(details)
        potential_source
      end

      sig do
        params(
          details: T.nilable(T.any(String, T::Array[String], T::Hash[String, String]))
        ).returns(T.nilable(String))
      end
      def get_url(details)
        return unless details

        url =
          case details
          when String then details
          when Hash then details.fetch("url", nil)
          when Array
            # Try to find the first valid URL string, and if not, return the first string (even if it isn't a URL)
            details.find { |d| d.is_a?(String) && d.match?(%r{^[\w.-]+/[\w.-]+$}) } ||
            details.find { |d| d.is_a?(String) }
          end
        return url unless url&.match?(%r{^[\w.-]+/[\w.-]+$})

        "https://github.com/" + url
      end

      sig do
        params(
          details: T.nilable(T.any(String, T::Array[T.untyped], T::Hash[String, T.untyped]))
        )
          .returns(T.nilable(String))
      end
      def get_directory(details)
        # Only return a directory if it is explicitly specified
        return unless details.is_a?(Hash)

        details.fetch("directory", nil)
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def find_source_from_git_url
        url = new_source&.[](:url) || new_source&.fetch("url")
        Source.from_url(url)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def latest_version_listing
        return @latest_version_listing if defined?(@latest_version_listing) && @latest_version_listing

        @latest_version_listing = T.let({}, T.nilable(T::Hash[String, T.untyped]))

        response = Dependabot::RegistryClient.get(url: "#{dependency_url}/latest", headers: registry_auth_headers)
        @latest_version_listing = JSON.parse(response.body) if response.status == 200

        @latest_version_listing
      rescue JSON::ParserError, Excon::Error::Timeout
        @latest_version_listing
      end

      sig { returns(T::Array[[String, T::Hash[String, T.untyped]]]) }
      def all_version_listings
        return [] if npm_listing["versions"].nil?

        npm_listing["versions"]
          .reject { |_, details| details["deprecated"] }
          .sort_by { |version, _| NpmAndYarn::Version.new(version) }
          .reverse
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def npm_listing
        return @npm_listing if defined?(@npm_listing) && @npm_listing

        @npm_listing = T.let({}, T.nilable(T::Hash[String, T.untyped]))

        response = Dependabot::RegistryClient.get(url: dependency_url, headers: registry_auth_headers)
        return T.must(@npm_listing) if response.status >= 500

        begin
          @npm_listing = JSON.parse(response.body)
        rescue JSON::ParserError
          raise unless non_standard_registry?
        end

        @npm_listing
      rescue Excon::Error::Timeout
        @npm_listing
      end

      sig { returns(String) }
      def dependency_url
        registry_url =
          if new_source.nil?
            # Check credentials for a configured registry before falling back to public registry
            configured_registry_from_credentials || "https://registry.npmjs.org"
          else
            new_source&.fetch(:url)
          end

        # Remove trailing slashes and escape spaces for proper URL formatting
        registry_url = URI::DEFAULT_PARSER.escape(registry_url)&.gsub(%r{/+$}, "")

        # NPM registries expect slashes to be escaped
        escaped_dependency_name = dependency.name.gsub("/", "%2F")
        "#{registry_url}/#{escaped_dependency_name}"
      end

      sig { returns(T::Hash[String, String]) }
      def registry_auth_headers
        return {} unless auth_token

        { "Authorization" => "Bearer #{auth_token}" }
      end

      sig { returns(T.nilable(String)) }
      def configured_registry_from_credentials
        # Look for a credential that replaces the base registry (global registry replacement)
        replaces_base_cred = credentials.find { |cred| cred["type"] == "npm_registry" && cred.replaces_base? }
        return normalize_registry_url(replaces_base_cred["registry"]) if replaces_base_cred

        nil
      end

      sig { params(registry: T.nilable(String)).returns(T.nilable(String)) }
      def normalize_registry_url(registry)
        return nil unless registry
        return registry if registry.start_with?("http")

        "https://#{registry}"
      end

      sig { returns(String) }
      def dependency_registry
        if new_source.nil? then "registry.npmjs.org"
        else
          new_source&.fetch(:url)&.gsub("https://", "")&.gsub("http://", "")
        end
      end

      sig { returns(T.nilable(String)) }
      def auth_token
        credentials
          .select { |cred| cred["type"] == "npm_registry" }
          .find { |cred| cred["registry"] == dependency_registry }
          &.fetch("token", nil)
      end

      sig { returns(T::Boolean) }
      def non_standard_registry?
        dependency_registry != "registry.npmjs.org"
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("npm_and_yarn", Dependabot::NpmAndYarn::MetadataFinder)

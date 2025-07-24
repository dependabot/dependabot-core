# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/helm/version"
require "dependabot/docker/requirement"
require "dependabot/shared/utils/credentials_finder"
require "dependabot/shared_helpers"
require "excon"
require "yaml"
require "json"
require "dependabot/helm/helpers"

module Dependabot
  module Helm
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_resolver"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(fetch_latest_version, T.nilable(T.any(String, Gem::Version)))
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        dependency.version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        dependency.requirements.map do |req|
          updated_metadata = req.fetch(:metadata).dup
          updated_req = req.dup
          updated_req[:requirement] = latest_version.to_s if updated_metadata.key?(:type)

          updated_req
        end
      end

      private

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig do
        params(chart_name: String, repo_name: T.nilable(String),
               repo_url: T.nilable(String)).returns(T.nilable(Gem::Version))
      end
      def fetch_releases_with_helm_cli(chart_name, repo_name, repo_url)
        Dependabot.logger.info("Attempting to search for #{chart_name} using helm CLI")
        releases = fetch_chart_releases(chart_name, repo_name, repo_url)

        return nil unless releases && !releases.empty?

        valid_releases = filter_valid_releases(releases)
        return nil if valid_releases.empty?

        if should_skip_cooldown?
          valid_releases =  latest_version_resolver
                            .fetch_tag_and_release_date_helm_chart(valid_releases, repo_name, chart_name)
        end
        highest_release = valid_releases.max_by { |release| version_class.new(release["version"]) }
        Dependabot.logger.info(
          "Found latest version #{T.must(highest_release)['version']} for #{chart_name} using helm search"
        )
        version_class.new(T.must(highest_release)["version"])
      end

      sig { params(chart_name: String, repo_url: T.nilable(String)).returns(T.nilable(Gem::Version)) }
      def fetch_releases_from_index(chart_name, repo_url)
        Dependabot.logger.info("Falling back to index.yaml search for #{chart_name}")
        return nil unless repo_url

        index_url = build_index_url(repo_url)
        index = fetch_helm_chart_index(index_url)
        return nil unless index && index["entries"] && index["entries"][chart_name]

        all_versions = index["entries"][chart_name].map { |entry| entry["version"] }
        Dependabot.logger.info("Found #{all_versions.length} versions for #{chart_name} in index.yaml")

        valid_versions = filter_valid_versions(all_versions)
        if should_skip_cooldown?
          # Filter out versions that are in cooldown period
          valid_versions = latest_version_resolver.fetch_tag_and_release_date_helm_chart_index(
            index_url,
            valid_versions,
            chart_name
          )
        end
        Dependabot.logger.info("After filtering, found #{valid_versions.length} valid versions for #{chart_name}")

        return nil if valid_versions.empty?

        highest_version = valid_versions.map { |v| version_class.new(v) }.max
        Dependabot.logger.info("Highest valid version for #{chart_name} is #{highest_version}")

        highest_version
      end

      sig { params(releases: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
      def filter_valid_releases(releases)
        releases.reject do |release|
          version_class.new(release["version"]) <= version_class.new(dependency.version) ||
            ignore_requirements.any? { |r| r.satisfied_by?(version_class.new(release["version"])) }
        end
      end

      sig { params(repo_url: String).returns(String) }
      def build_index_url(repo_url)
        repo_url_trimmed = repo_url.strip.chomp("/")
        normalized_repo_url = repo_url_trimmed.gsub("oci://", "https://")

        "#{normalized_repo_url}/index.yaml"
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def version_can_update?(requirements_to_unlock:) # rubocop:disable Lint/UnusedMethodArgument
        return false unless latest_version

        version_class.new(latest_version.to_s) > version_class.new(dependency.version)
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_version
        case dependency_type
        when :helm_chart
          fetch_latest_chart_version
        when :docker_image
          fetch_latest_image_version
        else
          Gem::Version.new(dependency.version)
        end
      end

      sig { returns(Symbol) }
      def dependency_type
        req = dependency.requirements.first
        type = T.must(req).dig(:metadata, :type)

        type || :unknown
      end

      sig do
        params(chart_name: String, repo_name: T.nilable(String),
               repo_url: T.nilable(String)).returns(T.nilable(T::Array[T::Hash[String, T.untyped]]))
      end
      def fetch_chart_releases(chart_name, repo_name = nil, repo_url = nil)
        Dependabot.logger.info("Fetching releases for Helm chart: #{chart_name}")

        if repo_name && repo_url
          authenticate_registry_source(repo_url)
          begin
            Helpers.add_repo(repo_name, repo_url)
            Helpers.update_repo
          rescue StandardError => e
            Dependabot.logger.error("Error adding/updating Helm repository: #{e.message}")
          end
        end

        begin
          search_command = repo_name ? "#{repo_name}/#{chart_name}" : chart_name
          Dependabot.logger.info("Searching for: #{search_command}")

          json_output = Helpers.search_releases(search_command)
          return nil if json_output.empty?

          releases = JSON.parse(json_output)
          Dependabot.logger.info("Found #{releases.length} releases for #{chart_name}")
          releases
        rescue StandardError => e
          Dependabot.logger.error("Error fetching chart releases: #{e.message}")
          nil
        end
      end

      sig { params(repo_url: T.nilable(String)).returns(T.nilable(String)) }
      def authenticate_registry_source(repo_url)
        return unless repo_url

        repo_creds = Shared::Utils::CredentialsFinder.new(@credentials, private_repository_type: "helm_registry")
                                                     .credentials_for_registry(repo_url)
        return unless repo_creds

        Helpers.registry_login(T.must(repo_creds["username"]), T.must(repo_creds["password"]), repo_url)
      rescue StandardError
        raise PrivateSourceAuthenticationFailure, repo_url
      end

      sig { params(repo_url: T.nilable(String)).returns(T.nilable(String)) }
      def authenticate_oci_registry_source(repo_url)
        return unless repo_url

        repo_creds = Shared::Utils::CredentialsFinder.new(@credentials, private_repository_type: "helm_registry")
                                                     .credentials_for_registry(repo_url)
        return unless repo_creds

        Helpers.oci_registry_login(T.must(repo_creds["username"]), T.must(repo_creds["password"]), repo_url)
      rescue StandardError
        raise PrivateSourceAuthenticationFailure, repo_url
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_chart_version
        chart_name = dependency.name
        source = dependency.requirements.first&.dig(:source)
        repo_url = source&.dig(:registry)
        repo_name = extract_repo_name(repo_url)
        releases = fetch_releases_with_helm_cli(chart_name, repo_name, repo_url)
        return releases if releases

        tag = fetch_latest_oci_tag(chart_name, repo_url) if repo_url&.start_with?("oci://")
        return tag if tag

        fetch_releases_from_index(chart_name, repo_url)
      end

      sig { params(chart_name: String, repo_url: String).returns(T.nilable(Gem::Version)) }
      def fetch_latest_oci_tag(chart_name, repo_url)
        tags = fetch_oci_tags(chart_name, repo_url)
        return nil unless tags && !tags.empty?

        valid_tags = filter_valid_versions(tags)
        if should_skip_cooldown?
          # Filter out versions that are in cooldown period
          repo_url = repo_url.gsub("oci://", "")
          repo_url = repo_url + "/" + chart_name
          tags_with_release_date = fetch_tags_with_release_date_using_oci(valid_tags, repo_url)
          valid_tags = latest_version_resolver.filter_versions_in_cooldown_period_using_oci(
            valid_tags,
            tags_with_release_date
          )
        end
        return nil if valid_tags.empty?

        highest_tag = valid_tags.map { |v| version_class.new(v) }.max
        Dependabot.logger.info("Highest valid OCI tag for #{chart_name} is #{highest_tag}")
        highest_tag
      end

      sig { params(chart_name: String, repo_url: String).returns(T.nilable(T::Array[String])) }
      def fetch_oci_tags(chart_name, repo_url)
        Dependabot.logger.info("Fetching OCI tags for #{repo_url}")
        oci_registry = repo_url.gsub("oci://", "")
        authenticate_oci_registry_source(repo_url)

        release_tags = Helpers.fetch_oci_tags("#{oci_registry}/#{chart_name}").split("\n")
        release_tags.map { |tag| tag.tr("_", "+") }
      end

      sig { params(repo_url: T.nilable(String)).returns(T.nilable(String)) }
      def extract_repo_name(repo_url)
        return nil unless repo_url

        name = repo_url.gsub(%r{^https?://}, "")
        name = name.chomp("/")
        name = name.gsub(/[^a-zA-Z0-9-]/, "-")
        name = "repo-#{name}" unless name.match?(/^[a-zA-Z0-9]/)

        name
      end

      sig { params(index_url: String).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def fetch_helm_chart_index(index_url)
        Dependabot.logger.info("Fetching Helm chart index from #{index_url}")

        response = Excon.get(
          index_url,
          idempotent: true,
          middlewares: Excon.defaults[:middlewares] + [Excon::Middleware::RedirectFollower]
        )

        Dependabot.logger.info("Received response from #{index_url} with status #{response.status}")
        parsed_result = YAML.safe_load(response.body)

        unless parsed_result.is_a?(Hash)
          raise Dependabot::DependencyFileNotParseable, "Expected YAML to parse into a Hash, got String instead"
        end

        parsed_result
      rescue Excon::Error => e
        Dependabot.logger.error("Error fetching Helm index from #{index_url}: #{e.message}")
        nil
      rescue StandardError => e
        Dependabot.logger.error("Error parsing Helm index: #{e.message}")
        nil
      end

      sig { params(all_versions: T::Array[String]).returns(T::Array[String]) }
      def filter_valid_versions(all_versions)
        all_versions.reject do |version|
          version_class.new(version) <= version_class.new(dependency.version) ||
            ignore_requirements.any? { |r| r.satisfied_by?(version_class.new(version)) }
        end
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_image_version
        docker_dependency = build_docker_dependency

        Dependabot.logger.info("Delegating to Docker UpdateChecker for image: #{docker_dependency.name}")

        docker_checker = Dependabot::UpdateCheckers.for_package_manager("docker").new(
          dependency: docker_dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories,
          raise_on_ignored: raise_on_ignored
        )

        latest_version = docker_checker.latest_version

        Dependabot.logger.info("Docker UpdateChecker found latest version: #{latest_version || 'none'}")

        return unless docker_checker.can_update?(requirements_to_unlock: :none)

        version_class.new(latest_version)
      end

      sig { params(tags: T::Array[String], repo_url: String).returns(T::Array[GitTagWithDetail]) }
      def fetch_tags_with_release_date_using_oci(tags, repo_url)
        git_tag_with_release_date = T.let([], T::Array[GitTagWithDetail])
        return git_tag_with_release_date if tags.empty?

        tags = tags.sort.reverse.take(150) # Limit to 150 tags for performance
        tags.each do |tag|
          # Since the oras registry uses "_" instead of "+", this is a workaround
          # to ensure the tag is correctly formatted for the OCI registry.
          # This is necessary because some tags may contain "+" which is not valid in OCI tags.

          temp_tag = tag.tr("+", "_")
          response = Helpers.fetch_tags_with_release_date_using_oci(repo_url, temp_tag)
          next if response.strip.empty?

          parsed_response = JSON.parse(response)
          git_tag_with_release_date << GitTagWithDetail.new(
            tag: tag,
            release_date: parsed_response.dig("annotations", "org.opencontainers.image.created")
          )
        rescue JSON::ParserError => e
          Dependabot.logger.error("Failed to parse JSON response for tag #{tag}: #{e.message}")
        rescue StandardError => e
          Dependabot.logger.error("Error in fetching details for tag #{tag}: #{e.message}")
        end
        git_tag_with_release_date
      end

      sig { returns(Dependabot::Dependency) }
      def build_docker_dependency
        source = T.must(dependency.requirements.first)[:source]
        name = dependency.name
        version = dependency.version

        if source[:path]
          parts = source[:path].split(".")
          if parts.length > 1 && (parts.last == "tag" || parts.last == "image")
            # The actual image name might be in image.repository
            name = parts[0...-1].join(".")
          end
        end

        registry = source[:registry] || nil

        Dependency.new(
          name: name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            file: T.must(dependency.requirements.first)[:file],
            source: {
              registry: registry,
              tag: version
            }
          }],
          package_manager: "helm"
        )
      end

      sig { returns(T::Boolean) }
      def should_skip_cooldown?
        @update_cooldown.nil? || !cooldown_enabled? || !@update_cooldown.included?(dependency.name)
      end

      sig { returns(T::Boolean) }
      def cooldown_enabled?
        true
      end

      sig { returns(LatestVersionResolver) }
      def latest_version_resolver
        LatestVersionResolver.new(
          dependency: dependency,
          credentials: credentials,
          cooldown_options: update_cooldown
        )
      end
    end
  end
end
Dependabot::UpdateCheckers.register("helm", Dependabot::Helm::UpdateChecker)

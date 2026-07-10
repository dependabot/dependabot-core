# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/requirements_update_strategy"
require "dependabot/helm/version"
require "dependabot/helm/requirement"
require "dependabot/docker/requirement"
require "dependabot/shared/utils/credentials_finder"
require "dependabot/shared_helpers"
require "excon"
require "yaml"
require "json"
require "dependabot/helm/helpers"

module Dependabot
  module Helm
    # ClassLength is disabled to match sibling ecosystems' update checkers
    # (npm_and_yarn and bun disable it on the same class). The version-fetching
    # helpers already delegate to update_checker/latest_version_resolver;
    # further extraction would fragment the update-decision flow.
    class UpdateChecker < Dependabot::UpdateCheckers::Base # rubocop:disable Metrics/ClassLength
      extend T::Sig

      require_relative "update_checker/latest_version_resolver"
      require_relative "update_checker/requirements_updater"

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

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        updated_reqs = dependency.requirements.map do |req|
          case req.dig(:metadata, :type)
          when nil then req
          when :helm_chart then updated_chart_requirement(req)
          else req.merge(requirement: latest_version.to_s) # image deps: exact overwrite
          end
        end
        wrap_requirements(updated_reqs)
      end

      private

      # Helm stores each occurrence's constraint in the requirement's
      # source[:tag], not the requirement field (the shared parser leaves it
      # nil). Feed that constraint through the RequirementsUpdater so
      # versioning-strategy is honored. When no strategy is set we default to
      # BumpVersions, which preserves the authored operator and bumps the floor
      # (e.g. `^1.0.0` -> `^1.0.5`); exact pins stay exact (`1.0.0` -> `1.5.0`).
      sig { params(req: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement) }
      def updated_chart_requirement(req)
        current_constraint = chart_constraint_for(req)
        synthetic = T.cast(req.merge(requirement: current_constraint), Dependabot::DependencyRequirement)

        T.must(
          RequirementsUpdater.new(
            requirements: [synthetic],
            update_strategy: resolved_update_strategy,
            latest_resolvable_version: T.must(latest_version).to_s
          ).updated_requirements.first
        )
      end

      # The authored constraint for a single requirement. Prefer the
      # requirement's own source[:tag] over dependency.version, since
      # DependencySet may merge several same-named occurrences (different files
      # or ranges) into one dependency with a single combined version.
      sig { params(req: Dependabot::DependencyRequirement).returns(String) }
      def chart_constraint_for(req)
        (req[:requirement] || req.dig(:source, :tag) || dependency.version).to_s
      end

      sig { returns(Dependabot::RequirementsUpdateStrategy) }
      def resolved_update_strategy
        requirements_update_strategy || RequirementsUpdateStrategy::BumpVersions
      end

      # Overrides Base#current_version. For chart deps the Chart.yaml constraint
      # lives in dependency.version, which may be a range with no single version;
      # we anchor on its lower bound so candidate filtering has a concrete
      # baseline. Non-chart deps (docker images) keep the base behavior.
      sig { override.returns(T.nilable(Dependabot::Version)) }
      def current_version
        return super unless dependency_type == :helm_chart

        @current_version ||= T.let(chart_anchor_version, T.nilable(Dependabot::Version))
      end

      # A concrete version to anchor a chart constraint on. Single/lenient forms
      # (^1.0.0, ~1.2.0, 1.0.0) parse directly; comparator/hyphen/OR ranges do
      # not, so anchor on the lowest lower bound the Requirement parser reports
      # (0 when the constraint has no lower bound, e.g. "<2.0.0").
      sig { returns(Dependabot::Version) }
      def chart_anchor_version
        raw = dependency.version.to_s
        # A comparator/hyphen/OR constraint has no single version, and
        # version_class.new would silently mis-read it ("<2.0.0" -> 2.0.0), so
        # route those to the parser's lower bound.
        return min_bound_anchor(raw) if raw.match?(/[<>]|!=|\s-\s|\|\|/)

        begin
          version_class.new(raw)
        rescue StandardError
          min_bound_anchor(raw)
        end
      end

      # The lowest lower-bound version across the constraint's OR branches, or 0
      # when any branch has no lower bound (that branch permits arbitrarily low
      # versions, e.g. "<=2.0.0 || >=10.0.0"). Re-wrapped as a Helm::Version —
      # min_version yields a base Dependabot::Version, but Helm::Version#<=> only
      # accepts Helm operands.
      sig { params(raw: String).returns(Dependabot::Version) }
      def min_bound_anchor(raw)
        floors = Helm::Requirement.requirements_array(raw).map(&:min_version)
        return version_class.new("0") if floors.any?(&:nil?)

        floor = floors.compact.min
        floor ? version_class.new(floor.to_s) : version_class.new("0")
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig do
        params(
          chart_name: String,
          repo_name: T.nilable(String),
          repo_url: T.nilable(String)
        ).returns(T.nilable(Gem::Version))
      end
      def fetch_releases_with_helm_cli(chart_name, repo_name, repo_url)
        Dependabot.logger.info("Attempting to search for #{chart_name} using helm CLI")
        releases = fetch_chart_releases(chart_name, repo_name, repo_url)

        return nil unless releases && !releases.empty?

        valid_releases = filter_valid_releases(releases)
        return nil if valid_releases.empty?

        if cooldown_enabled?
          valid_releases =  latest_version_resolver
                            .fetch_tag_and_release_date_helm_chart(valid_releases, repo_name, chart_name)
        end
        highest_release = valid_releases.max_by { |release| version_class.new(T.cast(release["version"], String)) }
        Dependabot.logger.info(
          "Found latest version #{T.must(highest_release)['version']} for #{chart_name} using helm search"
        )
        version_class.new(T.cast(T.must(highest_release)["version"], String))
      end

      sig do
        params(index: T.nilable(T::Hash[String, Object]), chart_name: String)
          .returns(T.nilable(T::Array[T::Hash[String, Object]]))
      end
      def chart_entries_from_index(index, chart_name)
        entries = T.cast(index&.fetch("entries", nil), T.nilable(T::Hash[String, Object]))
        T.cast(entries&.fetch(chart_name, nil), T.nilable(T::Array[T::Hash[String, Object]]))
      end

      sig { params(chart_name: String, repo_url: T.nilable(String)).returns(T.nilable(Gem::Version)) }
      def fetch_releases_from_index(chart_name, repo_url)
        Dependabot.logger.info("Falling back to index.yaml search for #{chart_name}")
        return nil unless repo_url

        index_url = build_index_url(repo_url)
        index = fetch_helm_chart_index(index_url)
        chart_entries = chart_entries_from_index(index, chart_name)
        return nil unless chart_entries

        all_versions = chart_entries.map { |entry| T.cast(entry["version"], String) }
        Dependabot.logger.info("Found #{all_versions.length} versions for #{chart_name} in index.yaml")

        valid_versions = filter_valid_versions(all_versions)
        if cooldown_enabled?
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

      sig { params(releases: T::Array[T::Hash[String, Object]]).returns(T::Array[T::Hash[String, Object]]) }
      def filter_valid_releases(releases)
        releases.reject do |release|
          release_version = version_class.new(T.cast(release["version"], String))
          # Compare against current_version (the anchored floor) rather than
          # dependency.version: for a range constraint (">=1.0.0 <2.0.0") the raw
          # version string isn't a single parseable version.
          release_version <= current_version ||
            ignore_requirements.any? do |r|
              r.instance_of?(Dependabot::Requirement) && r.satisfied_by?(release_version)
            end
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
      def version_can_update?(requirements_to_unlock:)
        return false unless latest_version
        # Non-chart deps (docker images) keep the base behavior — including its
        # nilable current_version handling.
        return super unless dependency_type == :helm_chart

        return false unless version_class.new(latest_version.to_s) > T.must(current_version)

        # For a chart dependency, an "update" means the authored Chart.yaml
        # constraint actually changes. The RequirementsUpdater deliberately
        # leaves some constraints untouched (an in-range comparator/hyphen range,
        # or an OR range already satisfied by the latest version), so gate on
        # whether it would produce a different constraint. Otherwise can_update?
        # promises a change the file updater can't make, and it raises
        # "Expected content to change!" on the unchanged Chart.yaml.
        chart_requirement_changes?
      end

      # Whether running the authored chart constraint through the
      # RequirementsUpdater yields a different constraint string for *any*
      # requirement. A dependency may carry several requirements (same chart
      # name across files/entries); an update is warranted if even one changes.
      sig { returns(T::Boolean) }
      def chart_requirement_changes?
        chart_reqs = dependency.requirements.select { |r| r.dig(:metadata, :type) == :helm_chart }
        chart_reqs = dependency.requirements if chart_reqs.empty?
        return true if chart_reqs.empty?

        chart_reqs.any? do |req|
          updated_chart_requirement(req)[:requirement].to_s != chart_constraint_for(req)
        end
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
        params(
          chart_name: String,
          repo_name: T.nilable(String),
          repo_url: T.nilable(String)
        ).returns(T.nilable(T::Array[T::Hash[String, Object]]))
      end
      def fetch_chart_releases(chart_name, repo_name = nil, repo_url = nil)
        Dependabot.logger.info("Fetching releases for Helm chart: #{chart_name}")

        if repo_name && repo_url
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
        if cooldown_enabled?
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

        release_tags = Helpers.fetch_oci_tags("#{oci_registry}/#{chart_name}").split("\n")
        # Filter out tags that are not valid versions (e.g., SHA256 hashes, .sig, .att, .metadata files)
        release_tags = release_tags.select do |tag|
          # Skip tags that start with "sha256-" or end with .sig, .att, or .metadata
          next false if tag.start_with?("sha256-") || tag.end_with?(".sig", ".att", ".metadata")

          # Use Version.correct? to check if the tag is a valid version
          version_class.correct?(tag)
        end
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

      sig { params(index_url: String).returns(T.nilable(T::Hash[String, Object])) }
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
          version_class.new(version) <= current_version ||
            ignore_requirements.any? do |r|
              r.instance_of?(Dependabot::Requirement) && r.satisfied_by?(version_class.new(version))
            end
        end
      end

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_image_version
        docker_dependency = build_docker_dependency

        Dependabot.logger.info("Delegating to Docker UpdateChecker for image: #{docker_dependency.name}")

        docker_checker = if cooldown_enabled?
                           Dependabot::UpdateCheckers.for_package_manager("docker").new(
                             dependency: docker_dependency,
                             dependency_files: dependency_files,
                             credentials: credentials,
                             ignored_versions: ignored_versions,
                             security_advisories: security_advisories,
                             raise_on_ignored: raise_on_ignored,
                             update_cooldown: update_cooldown
                           )
                         else
                           Dependabot::UpdateCheckers.for_package_manager("docker").new(
                             dependency: docker_dependency,
                             dependency_files: dependency_files,
                             credentials: credentials,
                             ignored_versions: ignored_versions,
                             security_advisories: security_advisories,
                             raise_on_ignored: raise_on_ignored
                           )
                         end

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

          begin
            parsed_response = JSON.parse(response)
          rescue JSON::ParserError => e
            Dependabot.logger.error("Failed to parse JSON response for tag #{tag}: #{e.message}")
            next
          end
          git_tag_with_release_date << GitTagWithDetail.new(
            tag: tag,
            release_date: parsed_response.dig("annotations", "org.opencontainers.image.created")
          )
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
          package_manager: "docker"
        )
      end

      sig { returns(T::Boolean) }
      def cooldown_enabled?
        # This is a simple check to see if user has put cooldown days.
        # If not set, then we aassume user does not want cooldown.
        # Since Helm does not support Semver versioning, So option left
        # for the user is to set cooldown default days.
        return false if update_cooldown.nil?

        T.must(update_cooldown&.default_days).positive?
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

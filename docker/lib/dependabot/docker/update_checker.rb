# typed: strict
# frozen_string_literal: true

require "docker_registry2"
require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/docker/tag"
require "dependabot/docker/file_parser"
require "dependabot/docker/version"
require "dependabot/docker/requirement"
require "dependabot/shared/utils/credentials_finder"
require "dependabot/package/release_cooldown_options"
require "dependabot/package/package_release"
require "dependabot/experiments"

module Dependabot
  module Docker
    # rubocop:disable Metrics/ClassLength
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      MANIFEST_LIST_TYPES = T.let(
        [
          "application/vnd.docker.distribution.manifest.list.v2+json",
          "application/vnd.oci.image.index.v1+json"
        ].freeze,
        T::Array[String]
      )

      # Tolerance window for platform timestamp comparison.
      # Multi-arch CI builds may finish platforms at slightly different times.
      PLATFORM_TIMESTAMP_TOLERANCE_SECONDS = T.let(3 * 60 * 60, Integer)

      # Patterns that identify structurally obvious version components in tag
      # names. Matching parts are excluded from the common-component system
      # because they represent version data, not platform/variant identifiers.
      #
      # Everything that does NOT match these patterns is treated as a
      # platform/variant component (e.g., "alpine3", "ltsc2022", "bookworm",
      # "rc1", "jre"). This is intentionally broad — the primary tag filtering
      # in comparable_to? already handles prerelease and suffix isolation via
      # exact suffix matching, so component matching is a secondary safety net.
      #
      # To exclude a new structural pattern, add a regex here.
      VERSION_RELATED_PATTERNS = T.let(
        [
          /^\d+$/,                          # pure numbers: "123", "8"
          /^\d+\.\d+$/,                     # semver-like: "1.2"
          /^v\d+/,                          # v-prefixed: "v2", "v10"
          /^\d+[a-z]+\d+$/i,                # digit-letters-digit version parts: "0a1", "0b1", "0rc1"
          /^kb\d+$/i,                       # Microsoft KB numbers: "KB4505057"
          /^g[0-9a-f]{5,}$/,                # git SHAs: "g1a2b3c4"
          /^\d{8,14}$/,                     # timestamps: "20250909"
          /\d+_\d+/                         # underscore-separated version parts: "12_8"
        ].freeze,
        T::Array[Regexp]
      )

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_from(T.must(dependency.version))
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # Resolvability isn't an issue for Docker containers.
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for Docker containers
        dependency.version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |req|
          updated_source = req.fetch(:source).dup

          tag = req[:source][:tag]
          digest = req[:source][:digest]

          if tag
            updated_tag = latest_version_from(tag)
            updated_source[:tag] = updated_tag
            updated_source[:digest] = digest_of(updated_tag) if digest || pin_digests?
          elsif digest
            updated_source[:digest] = digest_of("latest")
          end

          req.merge(source: updated_source)
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for Dockerfiles
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def version_can_update?(requirements_to_unlock:) # rubocop:disable Lint/UnusedMethodArgument
        if digest_requirements.any?
          !digest_up_to_date?
        else
          !version_up_to_date?
        end
      end

      sig { returns(T::Boolean) }
      def version_up_to_date?
        if digest_requirements.any?
          version_tag_up_to_date? && digest_up_to_date?
        else
          version_tag_up_to_date?
        end
      end

      sig { returns(T::Boolean) }
      def version_tag_up_to_date?
        version = dependency.version
        return false unless version

        return true unless version_tag.comparable?

        latest_tag = latest_tag_from(version)

        # When timestamp validation is enabled, comparable_version_from strips
        # date components (e.g. 4.8.1-20251014 -> 4.8.1), so two dated tags
        # with different dates but the same base version compare as equal.
        # Detect this case by checking the tag names directly.
        if Dependabot::Experiments.enabled?(:docker_created_timestamp_validation) &&
           version_tag.dated_version? && latest_tag.dated_version? &&
           latest_tag.name != version_tag.name
          return false
        end

        comparable_version_from(latest_tag) <= comparable_version_from(version_tag)
      end

      sig { returns(T::Boolean) }
      def digest_up_to_date?
        digest_requirements.all? do |req|
          source = req.fetch(:source)
          source_digest = source.fetch(:digest)
          source_tag = source[:tag]

          expected_digest =
            if source_tag
              latest_tag = latest_tag_from(source_tag)
              digest_of(latest_tag.name)
            else
              updated_digest
            end

          # If we can't determine an expected digest (for example if the registry does not return digests)
          # assume it's up to date
          next true if expected_digest.nil?

          source_digest == expected_digest
        end
      end

      sig { params(version: String).returns(String) }
      def latest_version_from(version)
        latest_tag_from(version).name
      end

      sig { params(version: String).returns(Dependabot::Docker::Tag) }
      def latest_tag_from(version)
        @tags ||= T.let({}, T.nilable(T::Hash[String, Dependabot::Docker::Tag]))
        return T.must(@tags[version]) if @tags.key?(version)

        @tags[version] = fetch_latest_tag(Tag.new(version))
      end

      # NOTE: It's important that this *always* returns a tag (even if
      # it's the existing one) as it is what we later check the digest of.
      sig { params(version_tag: Dependabot::Docker::Tag).returns(Dependabot::Docker::Tag) }
      def fetch_latest_tag(version_tag)
        return Tag.new(T.must(latest_digest)) if version_tag.digest? && latest_digest
        return version_tag unless version_tag.comparable?

        # Prune out any downgrade tags before checking for pre-releases
        # (which requires a call to the registry for each tag, so can be slow)
        candidate_tags = comparable_tags_from_registry(version_tag)
        candidate_tags = remove_version_downgrades(candidate_tags, version_tag)
        candidate_tags = remove_prereleases(candidate_tags, version_tag)
        candidate_tags = filter_ignored(candidate_tags)
        candidate_tags = sort_tags(candidate_tags, version_tag)
        candidate_tags = apply_cooldown(candidate_tags)

        select_best_candidate(candidate_tags, version_tag)
      end

      sig do
        params(
          candidate_tags: T::Array[Dependabot::Docker::Tag],
          version_tag: Dependabot::Docker::Tag
        ).returns(Dependabot::Docker::Tag)
      end
      def select_best_candidate(candidate_tags, version_tag)
        same_precision_tags = remove_precision_changes(candidate_tags, version_tag)

        # Iterate from highest to lowest, trying each candidate until one passes validation
        candidate_tags.reverse_each do |candidate|
          selected = select_tag_with_precision(candidate, same_precision_tags, version_tag)
          validated = validate_tag_with_timestamp(selected, version_tag)
          return validated unless validated.name == version_tag.name && selected.name != version_tag.name
        end

        version_tag
      end

      sig do
        params(
          candidate: Dependabot::Docker::Tag,
          same_precision_tags: T::Array[Dependabot::Docker::Tag],
          version_tag: Dependabot::Docker::Tag
        ).returns(Dependabot::Docker::Tag)
      end
      def select_tag_with_precision(candidate, same_precision_tags, version_tag)
        return candidate if candidate.same_precision?(version_tag)

        # Find the highest same-precision tag that is <= this candidate
        best_same_precision = same_precision_tags.reverse.find do |t|
          comparable_version_from(t) <= comparable_version_from(candidate)
        end

        return candidate unless best_same_precision

        same_precision_digest = digest_of(best_same_precision.name)
        candidate_digest = digest_of(candidate.name)

        if same_precision_digest == candidate_digest &&
           best_same_precision.same_but_less_precise?(candidate)
          best_same_precision
        else
          candidate
        end
      end

      sig do
        params(
          selected_tag: Dependabot::Docker::Tag,
          current_tag: Dependabot::Docker::Tag
        ).returns(Dependabot::Docker::Tag)
      end
      def validate_tag_with_timestamp(selected_tag, current_tag)
        return selected_tag unless Dependabot::Experiments.enabled?(:docker_created_timestamp_validation)
        return selected_tag if selected_tag.name == current_tag.name

        if validate_candidate_platforms(selected_tag, current_tag)
          Dependabot.logger.info(
            "Platform validation: #{selected_tag.name} confirmed valid update from #{current_tag.name}"
          )
          return selected_tag
        end

        Dependabot.logger.info(
          "Platform validation: skipping #{selected_tag.name} — " \
          "platform check failed against #{current_tag.name}"
        )

        current_tag
      end

      sig { params(original_tag: Dependabot::Docker::Tag).returns(T::Array[Dependabot::Docker::Tag]) }
      def comparable_tags_from_registry(original_tag)
        common_components = identify_common_components(tags_from_registry)
        original_components = extract_tag_components(original_tag.name, common_components)
        Dependabot.logger.info("Original tag components: #{original_components.join(',')}")

        tags_from_registry.select do |tag|
          tag.comparable_to?(original_tag) &&
            (original_components.empty? ||
              compatible_components?(extract_tag_components(tag.name, common_components), original_components))
        end
      end

      sig do
        params(candidate_tags: T::Array[Dependabot::Docker::Tag])
          .returns(T::Array[Dependabot::Docker::Tag])
      end
      def apply_cooldown(candidate_tags)
        return candidate_tags if should_skip_cooldown?

        candidate_tags.reverse_each do |tag|
          details = publication_detail(tag)

          next if !details || !details.released_at

          return [tag] unless cooldown_period?(details.released_at)

          Dependabot.logger.info("Skipping tag #{tag.name} due to cooldown period")
        end

        []
      end

      sig { params(candidate_tag: Dependabot::Docker::Tag).returns(T.nilable(Dependabot::Package::PackageRelease)) }
      def publication_detail(candidate_tag)
        return publication_details[candidate_tag.name] if publication_details.key?(candidate_tag.name)

        details = get_tag_publication_details(candidate_tag)
        publication_details[candidate_tag.name] = T.cast(details, Dependabot::Package::PackageRelease)

        details
      end

      sig { params(tag: Dependabot::Docker::Tag).returns(T.nilable(Dependabot::Package::PackageRelease)) }
      def get_tag_publication_details(tag)
        digest_info = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          client = docker_registry_client
          client.digest(docker_repo_name, tag.name)
        end

        first_digest = extract_digest_from_response(digest_info, tag)
        return nil unless first_digest

        blob_info = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          client = docker_registry_client
          client.dohead "v2/#{docker_repo_name}/blobs/#{first_digest}"
        end

        last_modified = blob_info.headers[:last_modified]
        published_date = last_modified ? Time.parse(last_modified) : nil

        Dependabot::Package::PackageRelease.new(
          version: Docker::Version.new(tag.name),
          released_at: published_date,
          latest: false,
          yanked: false,
          url: nil,
          package_type: "docker"
        )
      end

      sig do
        params(
          digest_info: T.untyped,
          tag: Dependabot::Docker::Tag
        ).returns(T.nilable(String))
      end
      def extract_digest_from_response(digest_info, tag)
        # digest_info can be either a String or an Array depending on the registry response
        case digest_info
        when Array
          if digest_info.empty?
            Dependabot.logger.warn(
              "Empty digest_info array for #{docker_repo_name}:#{tag.name}"
            )
            return nil
          end
          digest_info.first&.fetch("digest")
        when String
          digest_info
        else
          Dependabot.logger.warn(
            "Unexpected digest_info type for #{docker_repo_name}:#{tag.name}: " \
            "#{digest_info.class} (expected String or Array)"
          )
          nil
        end
      end

      sig do
        params(
          max_attempts: Integer,
          errors: T::Array[T.class_of(StandardError)],
          _blk: T.proc.returns(T.untyped)
        ).returns(T.untyped)
      end
      def with_retries(max_attempts: 3, errors: [], &_blk)
        attempt = 0
        begin
          attempt += 1
          yield
        rescue *errors
          raise if attempt >= max_attempts

          retry
        end
      end

      sig { returns(T::Hash[String, T.nilable(Dependabot::Package::PackageRelease)]) }
      def publication_details
        @publication_details ||= T.let(
          {},
          T.nilable(
            T::Hash[String, T.nilable(Dependabot::Package::PackageRelease)]
          )
        )
      end

      sig { params(tags: T::Array[Dependabot::Docker::Tag]).returns(T::Array[String]) }
      def identify_common_components(tags)
        tag_parts = tags.map do |tag|
          # replace version parts with VERSION
          processed_tag = tag.name.gsub(/\d+\.\d+\.\d+_\d+/, "VERSION")

          parts = processed_tag.split(%r{[-\./]})
          parts.reject(&:empty?)
        end

        part_counts = tag_parts.flatten.tally

        part_counts.select do |part|
          part.length > 1 &&
            part != "VERSION" &&
            !version_related_pattern?(part)
        end.keys
      end

      sig { params(part: String).returns(T::Boolean) }
      def version_related_pattern?(part)
        VERSION_RELATED_PATTERNS.any? { |pattern| part.match?(pattern) }
      end

      sig { params(tag_name: String, common_components: T::Array[String]).returns(T::Array[String]) }
      def extract_tag_components(tag_name, common_components)
        common_components.select { |component| tag_name.match?(/\b#{Regexp.escape(component)}\b/) }
      end

      sig { params(tag_components: T::Array[String], original_components: T::Array[String]).returns(T::Boolean) }
      def compatible_components?(tag_components, original_components)
        tag_components.sort == original_components.sort
      end

      sig do
        params(
          candidate_tags: T::Array[Dependabot::Docker::Tag],
          version_tag: Dependabot::Docker::Tag
        )
          .returns(T::Array[Dependabot::Docker::Tag])
      end
      def remove_version_downgrades(candidate_tags, version_tag)
        current_version = comparable_version_from(version_tag)

        candidate_tags.select do |tag|
          comparable_version_from(tag) >= current_version
        end
      end

      sig do
        params(
          candidate_tags: T::Array[Dependabot::Docker::Tag],
          version_tag: Dependabot::Docker::Tag
        )
          .returns(T::Array[Dependabot::Docker::Tag])
      end
      def remove_prereleases(candidate_tags, version_tag)
        return candidate_tags if prerelease?(version_tag)

        candidate_tags.reject { |tag| prerelease?(tag) }
      end

      sig do
        params(
          candidate_tags: T::Array[Dependabot::Docker::Tag],
          version_tag: Dependabot::Docker::Tag
        )
          .returns(T::Array[Dependabot::Docker::Tag])
      end
      def remove_precision_changes(candidate_tags, version_tag)
        candidate_tags.select do |tag|
          tag.same_precision?(version_tag)
        end
      end

      sig { returns(T.nilable(Dependabot::Docker::Tag)) }
      def latest_tag
        return unless latest_digest

        tags_from_registry
          .select(&:canonical?)
          .sort_by { |t| comparable_version_from(t) }
          .reverse
          .find { |t| digest_of(t.name) == latest_digest }
      end

      sig { returns(T.nilable(String)) }
      def updated_digest
        @updated_digest ||= T.let(
          if latest_tag_from(T.must(dependency.version)).digest?
            latest_digest
          else
            digest_of(T.cast(latest_version, String))
          end,
          T.nilable(String)
        )
      end

      sig { returns(T::Array[Dependabot::Docker::Tag]) }
      def tags_from_registry
        @tags_from_registry ||= T.let(
          begin
            client = docker_registry_client

            client.tags(docker_repo_name, auto_paginate: true).fetch("tags").map { |name| Tag.new(name) }
          rescue *transient_docker_errors
            attempt ||= 1
            attempt += 1
            raise if attempt > 3

            retry
          end,
          T.nilable(T::Array[Dependabot::Docker::Tag])
        )
      rescue DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden
        raise PrivateSourceAuthenticationFailure, registry_hostname
      rescue RestClient::Exceptions::OpenTimeout,
             RestClient::Exceptions::ReadTimeout
        raise if using_dockerhub?

        raise PrivateSourceTimedOut, T.must(registry_hostname)
      rescue RestClient::ServerBrokeConnection,
             RestClient::TooManyRequests
        raise PrivateSourceBadResponse, registry_hostname
      rescue JSON::ParserError => e
        if e.message.include?("unexpected token")
          raise DependencyFileNotResolvable, "Error while accessing docker image at #{registry_hostname}"
        end

        raise
      end

      sig { returns(T.nilable(String)) }
      def latest_digest
        return unless tags_from_registry.map(&:name).include?("latest")

        digest_of("latest")
      end

      sig { params(tag: String).returns(T.nilable(String)) }
      def digest_of(tag)
        @digests ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        return @digests[tag] if @digests.key?(tag)

        @digests[tag] = fetch_digest_of(tag)
      end

      sig { params(tag: String).returns(T.nilable(String)) }
      def fetch_digest_of(tag)
        docker_registry_client.manifest_digest(docker_repo_name, tag)&.delete_prefix("sha256:")
      rescue *transient_docker_errors => e
        attempt ||= 1
        attempt += 1
        return if attempt > 3 && e.is_a?(DockerRegistry2::NotFound)
        raise PrivateSourceBadResponse, registry_hostname if attempt > 3

        retry
      rescue DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden
        raise PrivateSourceAuthenticationFailure, registry_hostname
      rescue RestClient::ServerBrokeConnection,
             RestClient::TooManyRequests
        raise PrivateSourceBadResponse, registry_hostname
      rescue JSON::ParserError
        Dependabot.logger.info \
          "docker_registry_client.manifest_digest(#{docker_repo_name}, #{tag}) returned an empty string"
        nil
      end

      sig { returns(T::Array[T.class_of(StandardError)]) }
      def transient_docker_errors
        [
          RestClient::Exceptions::Timeout,
          RestClient::ServerBrokeConnection,
          RestClient::ServiceUnavailable,
          RestClient::InternalServerError,
          RestClient::BadGateway,
          DockerRegistry2::NotFound
        ]
      end

      sig { params(tag: Dependabot::Docker::Tag).returns(T::Boolean) }
      def prerelease?(tag)
        return true if tag.looks_like_prerelease?

        # Compare the numeric version against the version of the `latest` tag.
        return false unless latest_tag

        if comparable_version_from(tag) > comparable_version_from(T.must(latest_tag))
          Dependabot.logger.info \
            "The `latest` tag points to the same image as the `#{T.must(latest_tag).name}` image, " \
            "so dependabot is treating `#{tag.name}` as a pre-release. " \
            "The `latest` tag needs to point to `#{tag.name}` for Dependabot to consider it."

          true
        else
          false
        end
      end

      sig { params(tag: Dependabot::Docker::Tag).returns(Dependabot::Version) }
      def comparable_version_from(tag)
        version_class.new(tag.numeric_version)
      end

      sig { returns(T.nilable(String)) }
      def registry_hostname
        if dependency.requirements.first&.dig(:source, :registry)
          return T.must(dependency.requirements.first).dig(:source, :registry)
        end

        credentials_finder.base_registry
      end

      sig { returns(T::Boolean) }
      def using_dockerhub?
        registry_hostname == "registry.hub.docker.com"
      end

      sig { returns(T.nilable(Dependabot::Credential)) }
      def registry_credentials
        credentials_finder.credentials_for_registry(registry_hostname)
      end

      sig { returns(Dependabot::Shared::Utils::CredentialsFinder) }
      def credentials_finder
        @credentials_finder ||= T.let(
          Dependabot::Shared::Utils::CredentialsFinder.new(credentials),
          T.nilable(Dependabot::Shared::Utils::CredentialsFinder)
        )
      end

      sig { returns(String) }
      def docker_repo_name
        return dependency.name unless using_dockerhub?
        return dependency.name unless dependency.name.split("/").count < 2

        "library/#{dependency.name}"
      end

      # Defaults from https://github.com/deitch/docker_registry2/blob/bfde04144f0b7fd63c156a1aca83efe19ee78ffd/lib/registry/registry.rb#L26-L27
      DEFAULT_DOCKER_OPEN_TIMEOUT_IN_SECONDS = 2
      DEFAULT_DOCKER_READ_TIMEOUT_IN_SECONDS = 60

      sig { returns(DockerRegistry2::Registry) }
      def docker_registry_client
        @docker_registry_client ||= T.let(
          DockerRegistry2::Registry.new(
            "https://#{registry_hostname}",
            user: registry_credentials&.fetch("username", nil),
            password: registry_credentials&.fetch("password", nil),
            read_timeout: docker_read_timeout_in_seconds,
            open_timeout: docker_open_timeout_in_seconds,
            http_options: { proxy: ENV.fetch("HTTPS_PROXY", nil) }
          ),
          T.nilable(DockerRegistry2::Registry)
        )
      end

      sig { returns(Integer) }
      def docker_open_timeout_in_seconds
        ENV.fetch("DEPENDABOT_DOCKER_OPEN_TIMEOUT_IN_SECONDS", DEFAULT_DOCKER_OPEN_TIMEOUT_IN_SECONDS).to_i
      end

      sig { returns(Integer) }
      def docker_read_timeout_in_seconds
        ENV.fetch("DEPENDABOT_DOCKER_READ_TIMEOUT_IN_SECONDS", DEFAULT_DOCKER_READ_TIMEOUT_IN_SECONDS).to_i
      end

      sig do
        params(
          candidate_tags: T::Array[Dependabot::Docker::Tag],
          version_tag: Dependabot::Docker::Tag
        )
          .returns(T::Array[Dependabot::Docker::Tag])
      end
      def sort_tags(candidate_tags, version_tag)
        candidate_tags.sort { |tag_a, tag_b| compare_tags(tag_a, tag_b, version_tag) }
      end

      sig do
        params(
          tag_a: Dependabot::Docker::Tag,
          tag_b: Dependabot::Docker::Tag,
          version_tag: Dependabot::Docker::Tag
        ).returns(Integer)
      end
      def compare_tags(tag_a, tag_b, version_tag)
        version_cmp = comparable_version_from(tag_a) <=> comparable_version_from(tag_b)
        return version_cmp if version_cmp && version_cmp != 0

        precision_cmp = compare_precision(tag_a, tag_b, version_tag)
        return precision_cmp unless precision_cmp.zero?

        # When versions and precision are equal (e.g., dated tags with same base version),
        # use the raw version string as tiebreaker so newer dates sort higher
        ((tag_a.version || "") <=> (tag_b.version || "")) || 0
      end

      sig do
        params(
          tag_a: Dependabot::Docker::Tag,
          tag_b: Dependabot::Docker::Tag,
          version_tag: Dependabot::Docker::Tag
        ).returns(Integer)
      end
      def compare_precision(tag_a, tag_b, version_tag)
        a_match = tag_a.same_precision?(version_tag)
        b_match = tag_b.same_precision?(version_tag)
        return 1 if a_match && !b_match
        return -1 if b_match && !a_match

        0
      end

      sig { params(candidate_tags: T::Array[Dependabot::Docker::Tag]).returns(T::Array[Dependabot::Docker::Tag]) }
      def filter_ignored(candidate_tags)
        filtered =
          candidate_tags
          .reject do |tag|
            version = comparable_version_from(tag)
            ignore_requirements.any? { |r| r.satisfied_by?(version) }
          end
        if @raise_on_ignored &&
           filter_lower_versions(filtered).empty? &&
           filter_lower_versions(candidate_tags).any? &&
           digest_requirements.none?
          raise AllVersionsIgnored
        end

        filtered
      end

      sig { params(tags: T::Array[Dependabot::Docker::Tag]).returns(T::Array[Dependabot::Docker::Tag]) }
      def filter_lower_versions(tags)
        tags.select do |tag|
          comparable_version_from(tag) > comparable_version_from(version_tag)
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def digest_requirements
        dependency.requirements.select do |requirement|
          requirement.dig(:source, :digest)
        end
      end

      sig { returns(Dependabot::Docker::Tag) }
      def version_tag
        @version_tag ||= T.let(
          Tag.new(T.must(dependency.version)),
          T.nilable(Dependabot::Docker::Tag)
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

      sig { returns(T::Boolean) }
      def pin_digests?
        Dependabot::Experiments.enabled?(:docker_pin_digests)
      end

      sig do
        returns(Integer)
      end
      def cooldown_days_for
        cooldown = @update_cooldown

        T.must(cooldown).default_days
      end

      sig { params(release_date: T.untyped).returns(T::Boolean) }
      def cooldown_period?(release_date)
        days = cooldown_days_for
        (Time.now.to_i - release_date.to_i) < (days * 24 * 60 * 60)
      end

      # Fetches the "created" timestamp from the image config blob for a given tag.
      # This represents the actual build time, which is more reliable than semver
      # for determining which image is truly newer.
      sig { params(tag_name: String).returns(T.nilable(Time)) }
      def fetch_image_config_created(tag_name)
        return config_created_timestamps[tag_name] if config_created_timestamps.key?(tag_name)

        created = fetch_image_config_created_from_registry(tag_name)
        config_created_timestamps[tag_name] = created
        created
      rescue *transient_docker_errors, DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden, JSON::ParserError => e
        Dependabot.logger.info(
          "Failed to fetch config created timestamp for #{docker_repo_name}:#{tag_name}: #{e.message}"
        )
        config_created_timestamps[tag_name] = nil
        nil
      end

      sig { params(tag_name: String).returns(T.nilable(Time)) }
      def fetch_image_config_created_from_registry(tag_name)
        manifest = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.manifest(docker_repo_name, tag_name)
        end

        resolved = resolve_platform_manifest(manifest)
        return nil unless resolved

        config_digest = resolved.dig("config", "digest")
        return nil unless config_digest

        config_blob = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.doget("v2/#{docker_repo_name}/blobs/#{config_digest}")
        end

        config_data = JSON.parse(config_blob.body)
        created_str = config_data["created"]
        return nil unless created_str

        begin
          Time.parse(created_str)
        rescue ArgumentError => e
          Dependabot.logger.info(
            "Failed to parse config created timestamp for " \
            "#{docker_repo_name}:#{tag_name}: #{e.message}"
          )
          nil
        end
      end

      # Resolves a manifest to a single platform-specific manifest.
      # If the manifest is a manifest list (multi-arch), selects the most
      # appropriate platform (preferring linux/amd64).
      sig { params(manifest: T.untyped).returns(T.nilable(T::Hash[String, T.untyped])) }
      def resolve_platform_manifest(manifest)
        media_type = manifest["mediaType"] || manifest[:mediaType]

        unless MANIFEST_LIST_TYPES.include?(media_type)
          return manifest.is_a?(Hash) ? manifest : manifest.to_h
        end

        platform_digest = select_platform_digest(manifest)
        return nil unless platform_digest

        platform_manifest = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.doget("v2/#{docker_repo_name}/manifests/#{platform_digest}")
        end

        JSON.parse(platform_manifest.body)
      end

      # Selects the digest of the best platform-specific manifest from a manifest list,
      # preferring linux/amd64.
      sig { params(manifest: T.untyped).returns(T.nilable(String)) }
      def select_platform_digest(manifest)
        manifests = manifest["manifests"] || manifest[:manifests] || []
        return nil if manifests.empty?

        selected = find_amd64_manifest(manifests) || manifests.first
        selected&.dig("digest") || selected&.dig(:digest)
      end

      sig { params(manifests: T.untyped).returns(T.untyped) }
      def find_amd64_manifest(manifests)
        manifests.find do |m|
          platform = m["platform"] || m[:platform] || {}
          (platform["architecture"] || platform[:architecture]) == "amd64"
        end
      end

      # Validates that all platforms from the current tag are present in the
      # candidate tag and that each platform's image was built at the same time
      # (within tolerance) or newer. For single-platform current tags, falls
      # back to simple timestamp comparison.
      sig do
        params(
          candidate_tag: Dependabot::Docker::Tag,
          current_tag: Dependabot::Docker::Tag
        ).returns(T::Boolean)
      end
      def validate_candidate_platforms(candidate_tag, current_tag)
        current_platforms = fetch_manifest_platforms(current_tag.name)

        # Single-platform current tag — fall back to simple timestamp comparison
        return candidate_newer_by_created_date?(candidate_tag, current_tag) if current_platforms.nil?

        candidate_platforms = fetch_manifest_platforms(candidate_tag.name)

        # Candidate is single-platform but current is multi-platform
        if candidate_platforms.nil?
          Dependabot.logger.info(
            "Platform validation: #{candidate_tag.name} is single-platform " \
            "but #{current_tag.name} is multi-platform"
          )
          return false
        end

        # Check all current platforms exist in candidate
        current_keys = current_platforms.to_set { |p| platform_key(p) }
        candidate_keys = candidate_platforms.to_set { |p| platform_key(p) }
        missing = current_keys - candidate_keys

        unless missing.empty?
          Dependabot.logger.info(
            "Platform validation: #{candidate_tag.name} missing platforms: #{missing.to_a.join(', ')}"
          )
          return false
        end

        # Validate timestamps for each platform
        validate_platform_timestamps(candidate_tag, current_tag, current_keys)
      end

      sig do
        params(
          candidate_tag: Dependabot::Docker::Tag,
          current_tag: Dependabot::Docker::Tag,
          platform_keys: T::Set[String]
        ).returns(T::Boolean)
      end
      def validate_platform_timestamps(candidate_tag, current_tag, platform_keys)
        candidate_timestamps = fetch_all_platform_timestamps(candidate_tag.name)
        current_timestamps = fetch_all_platform_timestamps(current_tag.name)

        platform_keys.all? do |key|
          candidate_time = candidate_timestamps[key]
          current_time = current_timestamps[key]

          # Both nil → trust semver
          next true if candidate_time.nil? && current_time.nil?
          # Only candidate nil → can't confirm, conservative fail
          next false if candidate_time.nil?
          # Only current nil → trust semver
          next true if current_time.nil?

          candidate_time >= (current_time - PLATFORM_TIMESTAMP_TOLERANCE_SECONDS)
        end
      end

      sig do
        params(
          candidate_tag: Dependabot::Docker::Tag,
          current_tag: Dependabot::Docker::Tag
        ).returns(T::Boolean)
      end
      def candidate_newer_by_created_date?(candidate_tag, current_tag)
        candidate_created = fetch_image_config_created(candidate_tag.name)
        current_created = fetch_image_config_created(current_tag.name)

        # If both timestamps are unavailable, trust semver ordering
        return true if candidate_created.nil? && current_created.nil?

        # If only the candidate's timestamp is unavailable, we can't confirm it's newer
        return false if candidate_created.nil?

        # If only the current tag's timestamp is unavailable, trust semver ordering
        return true if current_created.nil?

        candidate_created > current_created
      end

      # Fetches the platform entries from a manifest list for a given tag.
      # Returns nil if the tag is a single-platform image (not a manifest list).
      sig { params(tag_name: String).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
      def fetch_manifest_platforms(tag_name)
        return manifest_platforms_cache[tag_name] if manifest_platforms_cache.key?(tag_name)

        platforms = fetch_manifest_platforms_from_registry(tag_name)
        manifest_platforms_cache[tag_name] = platforms
        platforms
      rescue *transient_docker_errors, DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden, JSON::ParserError => e
        Dependabot.logger.info(
          "Failed to fetch manifest platforms for #{docker_repo_name}:#{tag_name}: #{e.message}"
        )
        manifest_platforms_cache[tag_name] = nil
        nil
      end

      sig { params(tag_name: String).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
      def fetch_manifest_platforms_from_registry(tag_name)
        manifest = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.manifest(docker_repo_name, tag_name)
        end

        media_type = manifest["mediaType"] || manifest[:mediaType]
        return nil unless MANIFEST_LIST_TYPES.include?(media_type)

        manifests = manifest["manifests"] || manifest[:manifests] || []

        # Filter to actual image manifests (exclude attestations/signatures)
        manifests.filter_map { |m| extract_platform(m) }
      end

      sig { params(manifest_entry: T.untyped).returns(T.nilable(T::Hash[String, T.untyped])) }
      def extract_platform(manifest_entry)
        platform = manifest_entry["platform"] || manifest_entry[:platform]
        return unless platform

        os = platform["os"] || platform[:os]
        arch = platform["architecture"] || platform[:architecture]
        return unless os && arch

        platform
      end

      # Builds a normalized string key from a platform hash, e.g. "linux/amd64" or "linux/arm64/v8"
      sig { params(platform: T::Hash[T.any(String, Symbol), T.untyped]).returns(String) }
      def platform_key(platform)
        os = platform["os"] || platform[:os]
        arch = platform["architecture"] || platform[:architecture]
        variant = platform["variant"] || platform[:variant]

        key = "#{os}/#{arch}"
        key = "#{key}/#{variant}" if variant
        key
      end

      # Fetches the created timestamp for every platform in a tag's manifest list.
      # Returns a Hash mapping platform key (e.g. "linux/amd64") to Time.
      sig { params(tag_name: String).returns(T::Hash[String, T.nilable(Time)]) }
      def fetch_all_platform_timestamps(tag_name)
        return T.must(platform_timestamps_cache[tag_name]) if platform_timestamps_cache.key?(tag_name)

        timestamps = fetch_all_platform_timestamps_from_registry(tag_name)
        platform_timestamps_cache[tag_name] = timestamps
        timestamps
      rescue *transient_docker_errors, DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden, JSON::ParserError => e
        Dependabot.logger.info(
          "Failed to fetch platform timestamps for #{docker_repo_name}:#{tag_name}: #{e.message}"
        )
        platform_timestamps_cache[tag_name] = {}
        {}
      end

      sig { params(tag_name: String).returns(T::Hash[String, T.nilable(Time)]) }
      def fetch_all_platform_timestamps_from_registry(tag_name)
        manifest = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.manifest(docker_repo_name, tag_name)
        end

        media_type = manifest["mediaType"] || manifest[:mediaType]
        return {} unless MANIFEST_LIST_TYPES.include?(media_type)

        manifests = manifest["manifests"] || manifest[:manifests] || []
        collect_platform_timestamps(manifests)
      end

      sig { params(manifests: T.untyped).returns(T::Hash[String, T.nilable(Time)]) }
      def collect_platform_timestamps(manifests)
        timestamps = {}

        manifests.each do |m|
          platform = extract_platform(m)
          next unless platform

          digest = m["digest"] || m[:digest]
          next unless digest

          key = platform_key(platform)
          timestamps[key] = fetch_platform_created_timestamp(digest)
        end

        timestamps
      end

      sig { params(platform_digest: String).returns(T.nilable(Time)) }
      def fetch_platform_created_timestamp(platform_digest)
        platform_manifest = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.doget("v2/#{docker_repo_name}/manifests/#{platform_digest}")
        end

        parsed = JSON.parse(platform_manifest.body)
        config_digest = parsed.dig("config", "digest")
        return nil unless config_digest

        config_blob = with_retries(max_attempts: 3, errors: transient_docker_errors) do
          docker_registry_client.doget("v2/#{docker_repo_name}/blobs/#{config_digest}")
        end

        config_data = JSON.parse(config_blob.body)
        created_str = config_data["created"]
        return nil unless created_str

        Time.parse(created_str)
      rescue ArgumentError => e
        Dependabot.logger.info(
          "Failed to parse platform timestamp for #{docker_repo_name} digest #{platform_digest}: #{e.message}"
        )
        nil
      end

      sig { returns(T::Hash[String, T.nilable(T::Array[T::Hash[String, T.untyped]])]) }
      def manifest_platforms_cache
        @manifest_platforms_cache ||= T.let(
          {},
          T.nilable(T::Hash[String, T.nilable(T::Array[T::Hash[String, T.untyped]])])
        )
      end

      sig { returns(T::Hash[String, T::Hash[String, T.nilable(Time)]]) }
      def platform_timestamps_cache
        @platform_timestamps_cache ||= T.let(
          {},
          T.nilable(T::Hash[String, T::Hash[String, T.nilable(Time)]])
        )
      end

      sig { returns(T::Hash[String, T.nilable(Time)]) }
      def config_created_timestamps
        @config_created_timestamps ||= T.let(
          {},
          T.nilable(T::Hash[String, T.nilable(Time)])
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

Dependabot::UpdateCheckers.register("docker", Dependabot::Docker::UpdateChecker)

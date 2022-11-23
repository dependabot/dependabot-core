# frozen_string_literal: true

require "docker_registry2"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/docker/version"
require "dependabot/docker/requirement"
require "dependabot/docker/utils/credentials_finder"

module DockerRegistry2
  class Registry
    private

    # By default the Docker Registry client sets the Accept header to
    # `application/vnd.docker.distribution.manifest.v2+json`. This is fine for
    # most images, but for multi-architecture images, it fetches the digest of a
    # specific architecture instead of the digest for the multi-architecture
    # image. We override the header to tell the Docker API to vary its behavior
    # depending on whether the image is a uses a traditional (non-list) manifest
    # or a manifest list. If the image uses a traditional manifest, the API will
    # return the manifest digest. If the image uses a manifest list, the API
    # will return the manifest list digest.
    def headers(payload: nil, bearer_token: nil)
      headers = {}
      headers["Authorization"] = "Bearer #{bearer_token}" unless bearer_token.nil?
      if payload.nil?
        headers["Accept"] = %w(
          application/vnd.docker.distribution.manifest.v2+json
          application/vnd.docker.distribution.manifest.list.v2+json
          application/json
        ).join(",")
      end
      headers["Content-Type"] = "application/vnd.docker.distribution.manifest.v2+json" unless payload.nil?

      headers
    end
  end
end

module Dependabot
  module Docker
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      VERSION_REGEX = /v?(?<version>[0-9]+(?:\.[0-9]+)*(?:_[0-9]+|\.[a-z0-9]+|-(?:kb)?[0-9]+)*)/i
      VERSION_WITH_SFX = /^#{VERSION_REGEX}(?<suffix>-[a-z][a-z0-9.\-]*)?$/i
      VERSION_WITH_PFX = /^(?<prefix>[a-z][a-z0-9.\-]*-)?#{VERSION_REGEX}$/i
      VERSION_WITH_PFX_AND_SFX = /^(?<prefix>[a-z\-]+-)?#{VERSION_REGEX}(?<suffix>-[a-z\-]+)?$/i
      NAME_WITH_VERSION =
        /
          #{VERSION_WITH_PFX}|
          #{VERSION_WITH_SFX}|
          #{VERSION_WITH_PFX_AND_SFX}
      /x

      def latest_version
        latest_version_from(dependency.version)
      end

      def latest_resolvable_version
        # Resolvability isn't an issue for Docker containers.
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for Docker containers
        dependency.version
      end

      def updated_requirements
        dependency.requirements.map do |req|
          updated_source = req.fetch(:source).dup
          updated_source[:digest] = updated_digest if req[:source][:digest]
          updated_source[:tag] = latest_version_from(req[:source][:tag]) if req[:source][:tag]

          req.merge(source: updated_source)
        end
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for Dockerfiles
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def version_can_update?(*)
        !version_up_to_date?
      end

      def version_up_to_date?
        # If the tag isn't up-to-date then we can definitely update
        return false if version_tag_up_to_date?(dependency.version) == false
        return false if dependency.requirements.any? do |req|
                          version_tag_up_to_date?(req.fetch(:source, {})[:tag]) == false
                        end

        # Otherwise, if the Dockerfile specifies a digest check that that is
        # up-to-date
        digest_up_to_date?
      end

      def version_tag_up_to_date?(version)
        return unless version&.match?(NAME_WITH_VERSION)

        latest_version = fetch_latest_version(version)

        old_v = numeric_version_from(version)
        latest_v = numeric_version_from(latest_version)

        return true if version_class.new(latest_v) <= version_class.new(old_v)

        # Check the precision of the potentially higher tag is the same as the
        # one it would replace. In the event that it's not the same, check the
        # digests are also unequal. Avoids 'updating' ruby-2 -> ruby-2.5.1
        return false if precision_of(old_v) == precision_of(latest_v)

        digest_of(version) == digest_of(latest_version)
      end

      def digest_up_to_date?
        dependency.requirements.all? do |req|
          next true unless req.fetch(:source)[:digest]
          next true unless (new_digest = digest_of(dependency.version))

          req.fetch(:source).fetch(:digest) == new_digest
        end
      end

      def latest_version_from(version)
        @versions ||= {}
        return @versions[version] if @versions.key?(version)

        @versions[version] = fetch_latest_version(version)
      end

      # NOTE: It's important that this *always* returns a version (even if
      # it's the existing one) as it is what we later check the digest of.
      def fetch_latest_version(version)
        return version unless version.match?(NAME_WITH_VERSION)

        # Prune out any downgrade tags before checking for pre-releases
        # (which requires a call to the registry for each tag, so can be slow)
        candidate_tags = comparable_tags_from_registry(version)
        candidate_tags = remove_version_downgrades(candidate_tags, version)
        candidate_tags = remove_prereleases(candidate_tags, version)
        candidate_tags = filter_ignored(candidate_tags)
        candidate_tags = sort_tags(candidate_tags, version)

        latest_tag = candidate_tags.last

        if latest_tag && same_precision?(latest_tag, version)
          latest_tag
        else
          latest_same_precision_tag = remove_precision_changes(candidate_tags, version).last

          if latest_same_precision_tag && digest_of(latest_same_precision_tag) == digest_of(latest_tag)
            latest_same_precision_tag
          else
            latest_tag || version
          end
        end
      end

      def comparable_tags_from_registry(version)
        original_prefix = prefix_of(version)
        original_suffix = suffix_of(version)
        original_format = format_of(version)

        candidate_tags =
          tags_from_registry.
          select { |tag| tag.match?(NAME_WITH_VERSION) }.
          select { |tag| prefix_of(tag) == original_prefix }.
          select { |tag| format_of(tag) == original_format }
        return candidate_tags if original_format == :sha_suffixed

        candidate_tags.select { |tag| suffix_of(tag) == original_suffix }
      end

      def remove_version_downgrades(candidate_tags, version)
        candidate_tags.select do |tag|
          comparable_version_from(tag) >=
            comparable_version_from(version)
        end
      end

      def remove_prereleases(candidate_tags, version)
        return candidate_tags if prerelease?(version)

        candidate_tags.reject { |tag| prerelease?(tag) }
      end

      def remove_precision_changes(candidate_tags, version)
        candidate_tags.select do |tag|
          same_precision?(tag, version)
        end
      end

      def same_precision?(tag, another_tag)
        precision_of(numeric_version_from(tag)) == precision_of(numeric_version_from(another_tag))
      end

      def version_of_latest_tag
        return unless latest_digest

        candidate_tag =
          tags_from_registry.
          select { |tag| canonical_version?(tag) }.
          sort_by { |t| comparable_version_from(t) }.
          reverse.
          find { |t| digest_of(t) == latest_digest }

        return unless candidate_tag

        comparable_version_from(candidate_tag)
      end

      def canonical_version?(tag)
        return false unless numeric_version_from(tag)
        return true if tag == numeric_version_from(tag)

        # .NET tags are suffixed with -sdk
        return true if tag == numeric_version_from(tag) + "-sdk"

        tag == "jdk-" + numeric_version_from(tag)
      end

      def updated_digest
        @updated_digest ||= digest_of(latest_version)
      end

      def tags_from_registry
        @tags_from_registry ||=
          begin
            client = docker_registry_client

            client.tags(docker_repo_name, auto_paginate: true).fetch("tags")
          rescue *transient_docker_errors
            attempt ||= 1
            attempt += 1
            raise if attempt > 3

            retry
          end
      rescue DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden
        raise PrivateSourceAuthenticationFailure, registry_hostname
      rescue RestClient::Exceptions::OpenTimeout,
             RestClient::Exceptions::ReadTimeout
        raise if using_dockerhub?

        raise PrivateSourceTimedOut, registry_hostname
      end

      def latest_digest
        return unless tags_from_registry.include?("latest")

        digest_of("latest")
      end

      def digest_of(tag)
        @digests ||= {}
        return @digests[tag] if @digests.key?(tag)

        @digests[tag] =
          begin
            docker_registry_client.digest(docker_repo_name, tag)
          rescue *transient_docker_errors => e
            attempt ||= 1
            attempt += 1
            return if attempt > 3 && e.is_a?(DockerRegistry2::NotFound)
            raise if attempt > 3

            retry
          end
      rescue DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden
        raise PrivateSourceAuthenticationFailure, registry_hostname
      end

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

      def prefix_of(tag)
        tag.match(NAME_WITH_VERSION).named_captures.fetch("prefix")
      end

      def suffix_of(tag)
        tag.match(NAME_WITH_VERSION).named_captures.fetch("suffix")
      end

      def format_of(tag)
        version = numeric_version_from(tag)

        return :year_month if version.match?(/^[12]\d{3}(?:[.\-]|$)/)
        return :year_month_day if version.match?(/^[12]\d{5}(?:[.\-]|$)/)
        return :sha_suffixed if tag.match?(/(^|\-g?)[0-9a-f]{7,}$/)
        return :build_num if version.match?(/^\d+$/)

        :normal
      end

      def prerelease?(tag)
        return true if numeric_version_from(tag).gsub(/kb/i, "").match?(/[a-zA-Z]/)

        # If we're dealing with a numeric version we can compare it against
        # the digest for the `latest` tag.
        return false unless numeric_version_from(tag)
        return false unless latest_digest
        return false unless version_of_latest_tag

        comparable_version_from(tag) > version_of_latest_tag
      end

      def comparable_version_from(tag)
        version_class.new(numeric_version_from(tag))
      end

      def numeric_version_from(tag)
        return unless tag.match?(NAME_WITH_VERSION)

        tag.match(NAME_WITH_VERSION).named_captures.fetch("version").downcase
      end

      def registry_hostname
        return dependency.requirements.first[:source][:registry] if dependency.requirements.first[:source][:registry]

        credentials_finder.base_registry
      end

      def using_dockerhub?
        registry_hostname == "registry.hub.docker.com"
      end

      def registry_credentials
        credentials_finder.credentials_for_registry(registry_hostname)
      end

      def credentials_finder
        @credentials_finder ||= Utils::CredentialsFinder.new(credentials)
      end

      def docker_repo_name
        return dependency.name unless using_dockerhub?
        return dependency.name unless dependency.name.split("/").count < 2

        "library/#{dependency.name}"
      end

      def docker_registry_client
        @docker_registry_client ||=
          DockerRegistry2::Registry.new(
            "https://#{registry_hostname}",
            user: registry_credentials&.fetch("username", nil),
            password: registry_credentials&.fetch("password", nil),
            read_timeout: 10
          )
      end

      def sort_tags(candidate_tags, version)
        candidate_tags.sort do |tag_a, tag_b|
          if comparable_version_from(tag_a) > comparable_version_from(tag_b)
            1
          elsif comparable_version_from(tag_a) < comparable_version_from(tag_b)
            -1
          elsif same_precision?(tag_a, version)
            1
          elsif same_precision?(tag_b, version)
            -1
          else
            0
          end
        end
      end

      def precision_of(version)
        version.split(/[.-]/).length
      end

      def filter_ignored(candidate_tags)
        filtered =
          candidate_tags.
          reject do |tag|
            version = comparable_version_from(tag)
            ignore_requirements.any? { |r| r.satisfied_by?(version) }
          end
        if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(candidate_tags).any?
          raise AllVersionsIgnored
        end

        filtered
      end

      def filter_lower_versions(tags)
        versions_array = tags.map { |tag| comparable_version_from(tag) }
        versions_array.
          select { |version| version > comparable_version_from(dependency.version) }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("docker", Dependabot::Docker::UpdateChecker)

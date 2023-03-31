# frozen_string_literal: true

require "docker_registry2"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/docker/tag"
require "dependabot/docker/version"
require "dependabot/docker/requirement"
require "dependabot/docker/utils/credentials_finder"

module Dependabot
  module Docker
    class UpdateChecker < Dependabot::UpdateCheckers::Base
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
        if digest_requirements.any?
          !digest_up_to_date?
        else
          !version_up_to_date?
        end
      end

      def version_up_to_date?
        # If the tag isn't up-to-date then we can definitely update
        return false if version_tag_up_to_date?(dependency.version) == false
        return false if dependency.requirements.any? do |req|
                          version_tag_up_to_date?(req.fetch(:source, {})[:tag]) == false
                        end

        true
      end

      def version_tag_up_to_date?(version)
        return unless version

        version_tag = Tag.new(version)
        return unless version_tag.comparable?

        latest_tag = latest_tag_from(version)

        old_v = version_tag.numeric_version
        latest_v = latest_tag.numeric_version

        version_class.new(latest_v) <= version_class.new(old_v)
      end

      def digest_up_to_date?
        digest_requirements.all? do |req|
          next true unless updated_digest

          req.fetch(:source).fetch(:digest) == updated_digest
        end
      end

      def latest_version_from(version)
        latest_tag_from(version).name
      end

      def latest_tag_from(version)
        @tags ||= {}
        return @tags[version] if @tags.key?(version)

        @tags[version] = fetch_latest_tag(Tag.new(version))
      end

      # NOTE: It's important that this *always* returns a version (even if
      # it's the existing one) as it is what we later check the digest of.
      def fetch_latest_tag(version_tag)
        return version_tag unless version_tag.comparable?

        # Prune out any downgrade tags before checking for pre-releases
        # (which requires a call to the registry for each tag, so can be slow)
        candidate_tags = comparable_tags_from_registry(version_tag)
        candidate_tags = remove_version_downgrades(candidate_tags, version_tag)
        candidate_tags = remove_prereleases(candidate_tags, version_tag)
        candidate_tags = filter_ignored(candidate_tags)
        candidate_tags = sort_tags(candidate_tags, version_tag)

        latest_tag = candidate_tags.last
        return version_tag unless latest_tag

        return latest_tag if latest_tag.same_precision?(version_tag)

        latest_same_precision_tag = remove_precision_changes(candidate_tags, version_tag).last
        return latest_tag unless latest_same_precision_tag

        latest_same_precision_digest = digest_of(latest_same_precision_tag.name)
        latest_digest = digest_of(latest_tag.name)

        # NOTE: Some registries don't provide digests (the API documents them as
        # optional: https://docs.docker.com/registry/spec/api/#content-digests).
        #
        # In that case we can't know for sure whether the latest tag keeping
        # existing precision is the same as the absolute latest tag.
        #
        # We can however, make a best-effort to avoid unwanted changes by
        # directly looking at version numbers and checking whether the absolute
        # latest tag is just a more precise version of the latest tag that keeps
        # existing precision.

        if latest_same_precision_digest == latest_digest && latest_same_precision_tag.same_but_less_precise?(latest_tag)
          latest_same_precision_tag
        else
          latest_tag
        end
      end

      def comparable_tags_from_registry(original_tag)
        original_prefix = original_tag.prefix
        original_suffix = original_tag.suffix
        original_format = original_tag.format

        candidate_tags =
          tags_from_registry.
          select(&:comparable?).
          select { |tag| tag.prefix == original_prefix }.
          select { |tag| tag.format == original_format }
        return candidate_tags if original_format == :sha_suffixed

        candidate_tags.select { |tag| tag.suffix == original_suffix }
      end

      def remove_version_downgrades(candidate_tags, version_tag)
        candidate_tags.select do |tag|
          comparable_version_from(tag) >=
            comparable_version_from(version_tag)
        end
      end

      def remove_prereleases(candidate_tags, version_tag)
        return candidate_tags if prerelease?(version_tag)

        candidate_tags.reject { |tag| prerelease?(tag) }
      end

      def remove_precision_changes(candidate_tags, version_tag)
        candidate_tags.select do |tag|
          tag.same_precision?(version_tag)
        end
      end

      def version_of_latest_tag
        return unless latest_digest

        candidate_tag =
          tags_from_registry.
          select(&:canonical?).
          sort_by { |t| comparable_version_from(t) }.
          reverse.
          find { |t| digest_of(t.name) == latest_digest }

        return unless candidate_tag

        comparable_version_from(candidate_tag)
      end

      def updated_digest
        @updated_digest ||= digest_of(latest_version)
      end

      def tags_from_registry
        @tags_from_registry ||=
          begin
            client = docker_registry_client

            client.tags(docker_repo_name, auto_paginate: true).fetch("tags").map { |name| Tag.new(name) }
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
        return unless tags_from_registry.map(&:name).include?("latest")

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
            if attempt > 3 && e.is_a?(DockerRegistry2::NotFound)
              nil
            else
              raise if attempt > 3

              retry
            end
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

      def prerelease?(tag)
        return true if tag.numeric_version.gsub(/kb/i, "").match?(/[a-zA-Z]/)

        # If we're dealing with a numeric version we can compare it against
        # the digest for the `latest` tag.
        return false unless tag.numeric_version
        return false unless latest_digest
        return false unless version_of_latest_tag

        comparable_version_from(tag) > version_of_latest_tag
      end

      def comparable_version_from(tag)
        version_class.new(tag.numeric_version)
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
            read_timeout: 10,
            http_options: { proxy: ENV.fetch("HTTPS_PROXY", nil) }
          )
      end

      def sort_tags(candidate_tags, version_tag)
        candidate_tags.sort do |tag_a, tag_b|
          if comparable_version_from(tag_a) > comparable_version_from(tag_b)
            1
          elsif comparable_version_from(tag_a) < comparable_version_from(tag_b)
            -1
          elsif tag_a.same_precision?(version_tag)
            1
          elsif tag_b.same_precision?(version_tag)
            -1
          else
            0
          end
        end
      end

      def filter_ignored(candidate_tags)
        filtered =
          candidate_tags.
          reject do |tag|
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

      def filter_lower_versions(tags)
        versions_array = tags.map { |tag| comparable_version_from(tag) }
        versions_array.
          select { |version| version > comparable_version_from(Tag.new(dependency.version)) }
      end

      def digest_requirements
        dependency.requirements.select do |requirement|
          requirement.dig(:source, :digest)
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("docker", Dependabot::Docker::UpdateChecker)

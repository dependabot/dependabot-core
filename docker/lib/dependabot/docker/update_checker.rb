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
require "dependabot/docker/utils/credentials_finder"

module Dependabot
  module Docker
    # rubocop:disable Metrics/ClassLength
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

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
            updated_source[:digest] = digest_of(updated_tag) if digest
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

        comparable_version_from(latest_tag) <= comparable_version_from(version_tag)
      end

      sig { returns(T::Boolean) }
      def digest_up_to_date?
        digest_requirements.all? do |req|
          next true unless updated_digest

          req.fetch(:source).fetch(:digest) == updated_digest
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

      sig { params(original_tag: Dependabot::Docker::Tag).returns(T::Array[Dependabot::Docker::Tag]) }
      def comparable_tags_from_registry(original_tag)
        tags_from_registry.select { |tag| tag.comparable_to?(original_tag) }
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

      sig { returns(Dependabot::Docker::Utils::CredentialsFinder) }
      def credentials_finder
        @credentials_finder ||= T.let(
          Utils::CredentialsFinder.new(credentials),
          T.nilable(Dependabot::Docker::Utils::CredentialsFinder)
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
      DEFAULT_DOCKER_READ_TIMEOUT_IN_SECONDS = 5

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
    end
    # rubocop:enable Metrics/ClassLength
  end
end

Dependabot::UpdateCheckers.register("docker", Dependabot::Docker::UpdateChecker)

# frozen_string_literal: true

require "docker_registry2"

require "dependabot/update_checkers/base"
require "dependabot/errors"
require "dependabot/utils/docker/credentials_finder"

module Dependabot
  module UpdateCheckers
    module Docker
      class Docker < Dependabot::UpdateCheckers::Base
        VERSION_REGEX = /(?<version>[0-9]+(?:\.[a-zA-Z0-9]+)*)/.freeze
        VERSION_WTIH_SUFFIX =
          /^#{VERSION_REGEX}(?<affix>-[a-z0-9.\-]+)?$/.freeze
        VERSION_WTIH_PREFIX =
          /^(?<affix>[a-z0-9.\-]+-)?#{VERSION_REGEX}$/.freeze
        NAME_WITH_VERSION =
          /#{VERSION_WTIH_PREFIX}|#{VERSION_WTIH_SUFFIX}/.freeze

        def latest_version
          @latest_version ||= fetch_latest_version
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
            updated_source[:tag] = latest_version if req[:source][:tag]

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
          return false if version_tag_up_to_date? == false

          # Otherwise, if the Dockerfile specifies a digest check that that is
          # up-to-date
          digest_up_to_date?
        end

        def version_tag_up_to_date?
          return unless dependency.version.match?(NAME_WITH_VERSION)

          old_v = numeric_version_from(dependency.version)
          latest_v = numeric_version_from(latest_version)

          return true if version_class.new(latest_v) <= version_class.new(old_v)

          # Check the precision of the potentially higher tag is the same as the
          # one it would replace. In the event that it's not the same, check the
          # digests are also unequal. Avoids 'updating' ruby-2 -> ruby-2.5.1
          return false if old_v.split(".").count == latest_v.split(".").count

          digest_of(dependency.version) == digest_of(latest_version)
        end

        def digest_up_to_date?
          dependency.requirements.all? do |req|
            next true unless req.fetch(:source)[:digest]

            req.fetch(:source).fetch(:digest) == digest_of(dependency.version)
          end
        end

        # Note: It's important that this *always* returns a version (even if
        # it's the existing one) as it is what we later check the digest of.
        def fetch_latest_version
          unless dependency.version.match?(NAME_WITH_VERSION)
            return dependency.version
          end

          # Prune out any downgrade tags before checking for pre-releases
          # (which requires a call to the registry for each tag, so can be slow)
          candidate_tags = comparable_tags_from_registry
          non_downgrade_tags = remove_version_downgrades(candidate_tags)
          candidate_tags = non_downgrade_tags if non_downgrade_tags.any?

          wants_prerelease = prerelease?(dependency.version)
          candidate_tags =
            candidate_tags.
            reject { |tag| prerelease?(tag) && !wants_prerelease }.
            reject do |tag|
              version = version_class.new(numeric_version_from(tag))
              ignore_reqs.any? { |r| r.satisfied_by?(version) }
            end

          latest_tag =
            candidate_tags.
            max_by { |tag| version_class.new(numeric_version_from(tag)) }

          latest_tag || dependency.version
        end

        def comparable_tags_from_registry
          original_affix = affix_of(dependency.version)

          tags_from_registry.
            select { |tag| tag.match?(NAME_WITH_VERSION) }.
            select { |tag| affix_of(tag) == original_affix }.
            reject { |tag| commit_sha_suffix?(tag) }
        end

        def remove_version_downgrades(candidate_tags)
          candidate_tags.select do |tag|
            version_class.new(numeric_version_from(tag)) >=
              version_class.new(numeric_version_from(dependency.version))
          end
        end

        def commit_sha_suffix?(tag)
          # Some people suffix their versions with commit SHAs. Dependabot
          # can't order on those but will try to, so instead we should exclude
          # them (unless there's a `latest` version pushed to the registry, in
          # which case we'll use that to find the latest version)
          return false unless tag.match?(/(^|\-)[0-9a-f]{7,}$/)

          !tag.match?(/(^|\-)20[0-1]\d{5}$/)
        end

        def version_of_latest_tag
          return unless latest_digest

          tags_from_registry.
            select { |tag| canonical_version?(tag) }.
            select { |t| digest_of(t) == latest_digest }.
            map { |t| version_class.new(numeric_version_from(t)) }.
            max
        end

        def canonical_version?(tag)
          return false unless numeric_version_from(tag)
          return true if tag == numeric_version_from(tag)

          # .NET tags are suffixed with -sdk. There may be other cases we need
          # to consider in future, too.
          tag == numeric_version_from(tag) + "-sdk"
        end

        def updated_digest
          @updated_digest ||=
            begin
              docker_registry_client.digest(docker_repo_name, latest_version)
            rescue RestClient::Exceptions::Timeout
              attempt ||= 1
              attempt += 1
              raise if attempt > 3

              retry
            end
        rescue DockerRegistry2::RegistryAuthenticationException,
               RestClient::Forbidden
          raise PrivateSourceAuthenticationFailure, registry_hostname
        end

        def tags_from_registry
          @tags_from_registry ||=
            begin
              docker_registry_client.tags(docker_repo_name).fetch("tags")
            rescue RestClient::Exceptions::Timeout
              attempt ||= 1
              attempt += 1
              raise if attempt > 3

              retry
            end
        rescue DockerRegistry2::RegistryAuthenticationException,
               RestClient::Forbidden
          raise PrivateSourceAuthenticationFailure, registry_hostname
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
        end

        def transient_docker_errors
          [RestClient::Exceptions::Timeout, DockerRegistry2::NotFound]
        end

        def affix_of(tag)
          tag.match(NAME_WITH_VERSION).named_captures.fetch("affix")
        end

        def prerelease?(tag)
          return true if numeric_version_from(tag).match?(/[a-zA-Z]/)

          # If we're dealing with a numeric version we can compare it against
          # the digest for the `latest` tag.
          return false unless numeric_version_from(tag)
          return false unless latest_digest
          return false unless version_of_latest_tag

          version_class.new(numeric_version_from(tag)) > version_of_latest_tag
        end

        def numeric_version_from(tag)
          return unless tag.match?(NAME_WITH_VERSION)

          tag.match(NAME_WITH_VERSION).named_captures.fetch("version")
        end

        def registry_hostname
          dependency.requirements.first[:source][:registry] ||
            "registry.hub.docker.com"
        end

        def using_dockerhub?
          registry_hostname == "registry.hub.docker.com"
        end

        def registry_credentials
          credentials_finder.credentials_for_registry(registry_hostname)
        end

        def credentials_finder
          @credentials_finder ||=
            Utils::Docker::CredentialsFinder.new(credentials)
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
              user: registry_credentials&.fetch("username"),
              password: registry_credentials&.fetch("password")
            )
        end

        def ignore_reqs
          # Note: we use Gem::Requirement here because ignore conditions will
          # be passed as Ruby ranges
          ignored_versions.map { |req| Gem::Requirement.new(req.split(",")) }
        end
      end
    end
  end
end

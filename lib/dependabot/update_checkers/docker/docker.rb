# frozen_string_literal: true

require "docker_registry2"

require "dependabot/update_checkers/base"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Docker
      class Docker < Dependabot::UpdateCheckers::Base
        VERSION_REGEX = /(?<version>[0-9]+(?:\.[a-zA-Z0-9]+)*)/
        VERSION_WTIH_SUFFIX = /^#{VERSION_REGEX}(?<affix>-[a-z0-9.\-]+)?$/
        VERSION_WTIH_PREFIX = /^(?<affix>[a-z0-9.\-]+-)?#{VERSION_REGEX}$/
        NAME_WITH_VERSION = /#{VERSION_WTIH_PREFIX}|#{VERSION_WTIH_SUFFIX}/

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
            next req unless req.fetch(:source).fetch(:type) == "digest"
            next req unless updated_digest
            updated_source = req.fetch(:source).merge(digest: updated_digest)
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

        def version_up_to_date?
          return unless dependency.version.match?(NAME_WITH_VERSION)
          return unless latest_version

          original_version_number = numeric_version_from(dependency.version)
          latest_version_number = numeric_version_from(latest_version)

          Gem::Version.new(latest_version_number) <=
            Gem::Version.new(original_version_number)
        end

        def version_can_update?(*)
          return false unless dependency.version.match?(NAME_WITH_VERSION)
          return false unless latest_version

          !version_up_to_date?
        end

        def fetch_latest_version
          return nil unless dependency.version.match?(NAME_WITH_VERSION)
          original_affix = affix_of(dependency.version)
          wants_prerelease = prerelease?(dependency.version)

          tags_from_registry.
            select { |tag| tag.match?(NAME_WITH_VERSION) }.
            select { |tag| affix_of(tag) == original_affix }.
            reject { |tag| prerelease?(tag) && !wants_prerelease }.
            max_by { |tag| Gem::Version.new(numeric_version_from(tag)) }
        end

        def tags_from_registry
          attempt = 1
          @tags_from_registry ||=
            begin
              if dependency.name.split("/").count < 2
                docker_registry_client.
                  tags("library/#{dependency.name}").
                  fetch("tags")
              else
                docker_registry_client.
                  tags(dependency.name).
                  fetch("tags")
              end
            rescue RestClient::Exceptions::Timeout
              attempt += 1
              raise if attempt > 3
              retry
            end
        rescue DockerRegistry2::RegistryAuthenticationException
          raise PrivateSourceAuthenticationFailure, registry_hostname
        end

        def updated_digest
          return unless latest_version
          attempt = 1
          @updated_digest ||=
            begin
              image = dependency.name
              repo = image.split("/").count < 2 ? "library/#{image}" : image
              tag = latest_version

              docker_registry_client.
                dohead("/v2/#{repo}/manifests/#{tag}").
                headers.fetch(:docker_content_digest)
            rescue RestClient::Exceptions::Timeout
              attempt += 1
              raise if attempt > 3
              retry
            end
        rescue DockerRegistry2::RegistryAuthenticationException
          raise PrivateSourceAuthenticationFailure, registry_hostname
        end

        def affix_of(tag)
          tag.match(NAME_WITH_VERSION).named_captures.fetch("affix")
        end

        def prerelease?(tag)
          numeric_version_from(tag).match?(/[a-zA-Z]/)
        end

        def numeric_version_from(tag)
          tag.match(NAME_WITH_VERSION).named_captures.fetch("version")
        end

        def registry_hostname
          dependency.requirements.first[:source][:registry]
        end

        def registry_credentials
          credentials.
            select { |cred| cred["type"] == "docker_registry" }.
            find { |cred| cred["registry"] == registry_hostname }
        end

        def docker_registry_client
          @docker_registry_client ||=
            if registry_hostname
              DockerRegistry2::Registry.new(
                "https://#{registry_hostname}",
                user: registry_credentials&.fetch("username"),
                password: registry_credentials&.fetch("password")
              )
            else
              DockerRegistry2::Registry.new("https://registry.hub.docker.com")
            end
        end
      end
    end
  end
end

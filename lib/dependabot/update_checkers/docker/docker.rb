# frozen_string_literal: true

require "docker_registry2"

require "dependabot/update_checkers/base"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Docker
      class Docker < Dependabot::UpdateCheckers::Base
        VERSION_REGEX = /(?<version>[0-9]+(?:\.[a-zA-Z0-9]+)*)/
        VERSION_WTIH_SUFFIX = /^#{VERSION_REGEX}(?<affix>-[a-z0-9\-]+)?$/
        VERSION_WTIH_PREFIX = /^(?<affix>[a-z0-9\-]+-)?#{VERSION_REGEX}$/
        NAME_WITH_VERSION = /#{VERSION_WTIH_PREFIX}|#{VERSION_WTIH_SUFFIX}/

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # Resolvability isn't an issue for Docker containers.
          latest_version
        end

        def updated_requirements
          dependency.requirements
        end

        private

        def version_needs_update?
          return false unless dependency.version.match?(NAME_WITH_VERSION)
          return false unless latest_version

          original_version_number = numeric_version_from(dependency.version)
          latest_version_number = numeric_version_from(latest_version)

          Gem::Version.new(latest_version_number) >
            Gem::Version.new(original_version_number)
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
          @tags_from_registry ||=
            if dependency.name.split("/").count < 2
              docker_registry_client.
                tags("library/#{dependency.name}").
                fetch("tags")
            else
              docker_registry_client.
                tags(dependency.name).
                fetch("tags")
            end
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

        def private_registry_url
          dependency.requirements.first[:source][:registry]
        end

        def private_registry_credentials
          credentials.find { |cred| cred["registry"] == private_registry_url }
        end

        def docker_registry_client
          if private_registry_url && !private_registry_credentials
            raise PrivateSourceNotReachable, private_registry_url
          end

          @docker_registry_client ||=
            if private_registry_url
              DockerRegistry2::Registry.new(
                "https://#{private_registry_url}",
                user: private_registry_credentials["username"],
                password: private_registry_credentials["password"]
              )
            else
              DockerRegistry2::Registry.new("https://registry.hub.docker.com")
            end
        end
      end
    end
  end
end

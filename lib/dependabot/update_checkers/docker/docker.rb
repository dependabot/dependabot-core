# frozen_string_literal: true

require "docker_registry2"

require "dependabot/update_checkers/base"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Docker
      class Docker < Dependabot::UpdateCheckers::Base
        VERSION_REGEX = /^(?<version>[0-9]+\.[0-9]+(?:\.[a-zA-Z0-9]+)*)$/

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

        def fetch_latest_version
          return nil unless dependency.version.match?(VERSION_REGEX)

          tags =
            if dependency.name.split("/").count < 2
              docker_registry_client.tags("library/#{dependency.name}")
            else
              docker_registry_client.tags(dependency.name)
            end

          tags.fetch("tags").
            select { |tag| tag.match?(VERSION_REGEX) }.
            map { |tag| Gem::Version.new(tag) }.
            max
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

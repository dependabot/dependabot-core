# frozen_string_literal: true

require "docker_registry2"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/docker/utils/credentials_finder"

module Dependabot
  module Docker
    module FileParserHelper
      private

      def version_from(parsed_info)
        return parsed_info.fetch("tag") if parsed_info.fetch("tag")

        version_from_digest(
          registry: parsed_info.fetch("registry"),
          image: parsed_info.fetch("image"),
          digest: parsed_info.fetch("digest")
        )
      end

      def source_from(parsed_info)
        source = {}

        %w(registry tag digest).each do |part|
          value = parsed_info.fetch(part)
          source[part.to_sym] = value if value
        end

        source
      end

      def version_from_digest(registry:, image:, digest:)
        return unless digest

        repo = docker_repo_name(image, registry)
        client = docker_registry_client(registry)
        client.tags(repo, auto_paginate: true).fetch("tags").find do |tag|
          digest == client.digest(repo, tag)
        rescue DockerRegistry2::NotFound
          # Shouldn't happen, but it does. Example of existing tag with
          # no manifest is "library/python", "2-windowsservercore".
          false
        end
      rescue DockerRegistry2::RegistryAuthenticationException,
             RestClient::Forbidden
        raise if standard_registry?(registry)

        raise PrivateSourceAuthenticationFailure, registry
      end

      def docker_repo_name(image, registry)
        return image unless standard_registry?(registry)
        return image unless image.split("/").count < 2

        "library/#{image}"
      end

      def docker_registry_client(registry)
        if registry
          credentials = registry_credentials(registry)

          DockerRegistry2::Registry.new(
            "https://#{registry}",
            user: credentials&.fetch("username", nil),
            password: credentials&.fetch("password", nil)
          )
        else
          DockerRegistry2::Registry.new("https://registry.hub.docker.com")
        end
      end

      def registry_credentials(registry_url)
        credentials_finder.credentials_for_registry(registry_url)
      end

      def credentials_finder
        @credentials_finder ||= Utils::CredentialsFinder.new(credentials)
      end

      def standard_registry?(registry)
        return true if registry.nil?

        registry == "registry.hub.docker.com"
      end
    end
  end
end

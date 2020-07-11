# frozen_string_literal: true

require "docker_registry2"
require "dependabot/docker/utils/credentials_finder"

module Dependabot
  module Docker
    module Utils
      class DockerFileParser
        # Details of Docker regular expressions is at
        # https://github.com/docker/distribution/blob/master/reference/regexp.go
        DOMAIN_COMPONENT =
          /(?:[[:alnum:]]|[[:alnum:]][[[:alnum:]]-]*[[:alnum:]])/.freeze
        DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/.freeze
        REGISTRY = /(?<registry>#{DOMAIN}(?::\d+)?)/.freeze

        NAME_COMPONENT = /(?:[a-z\d]+(?:(?:[._]|__|[-]*)[a-z\d]+)*)/.freeze
        IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}.freeze

        FROM = /FROM/i.freeze
        TAG = /:(?<tag>[\w][\w.-]{0,127})/.freeze
        DIGEST = /@(?<digest>[^\s]+)/.freeze
        NAME = /\s+AS\s+(?<name>[\w-]+)/.freeze
        FROM_LINE =
          %r{^#{FROM}\s+(#{REGISTRY}/)?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?}.freeze

        AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+).amazonaws\.com/.freeze

        def initialize(line, credentials)
          parsed_from_line = FROM_LINE.match(line).named_captures
          if parsed_from_line["registry"] == "docker.io"
            parsed_from_line["registry"] = nil
          end
          @parsed_from_line = parsed_from_line
          @credentials = credentials
        end

        def source
          source_from(@parsed_from_line)
        end

        def image
          @parsed_from_line.fetch("image")
        end

        def version
          version_from(@parsed_from_line)
        end

        private

        def version_from(parsed_from_line)
          return parsed_from_line.fetch("tag") if parsed_from_line.fetch("tag")

          version_from_digest(
            registry: parsed_from_line.fetch("registry"),
            image: parsed_from_line.fetch("image"),
            digest: parsed_from_line.fetch("digest")
          )
        end

        def source_from(parsed_from_line)
          source = {}
          source[:type] = "docker"

          if parsed_from_line.fetch("image")
            source[:image] = parsed_from_line.fetch("image")
          end

          if parsed_from_line.fetch("registry")
            source[:registry] = parsed_from_line.fetch("registry")
          end

          if parsed_from_line.fetch("tag")
            source[:tag] = parsed_from_line.fetch("tag")
          end

          if parsed_from_line.fetch("digest")
            source[:digest] = parsed_from_line.fetch("digest")
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
          @credentials_finder ||= CredentialsFinder.new(@credentials)
        end

        def standard_registry?(registry)
          return true if registry.nil?

          registry == "registry.hub.docker.com"
        end
      end
    end
  end
end

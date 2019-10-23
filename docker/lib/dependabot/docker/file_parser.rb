# frozen_string_literal: true

require "docker_registry2"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require "dependabot/docker/utils/credentials_finder"

module Dependabot
  module Docker
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      # Details of Docker regular expressions is at
      # https://github.com/docker/distribution/blob/master/reference/regexp.go
      DOMAIN_COMPONENT =
        /(?:[[:alnum:]]|[[:alnum:]][[[:alnum:]]-]*[[:alnum:]])/.freeze
      DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/.freeze
      REGISTRY = /(?<registry>#{DOMAIN}(?::\d+)?)/.freeze

      NAME_COMPONENT = /(?:[a-z\d]+(?:(?:[._]|__|[-]*)[a-z\d]+)*)/.freeze
      IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}.freeze

      FROM = /FROM/i.freeze
      DRONE_IMAGE = /\s+image\:/i.freeze
      TAG = /:(?<tag>[\w][\w.-]{0,127})/.freeze
      DIGEST = /@(?<digest>[^\s]+)/.freeze
      NAME = /\s+AS\s+(?<name>[\w-]+)/.freeze
      FROM_LINE =
        %r{^#{FROM}\s+(#{REGISTRY}/)?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?}.freeze
      DRONE_IMAGE_LINE =
        %r{^#{DRONE_IMAGE}\s+(#{REGISTRY}/)?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?}.
        freeze

      AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+).amazonaws\.com/.freeze

      def parse
        dependency_set = DependencySet.new

        parse_docker_files(dependency_set, dockerfiles, FROM_LINE)
        parse_docker_files(dependency_set, drone_files, DRONE_IMAGE_LINE)

        dependency_set.dependencies
      end

      private

      def parse_docker_files(dependency_set, files, line_regex)
        files.each do |docker_file|
          docker_file.content.each_line do |line|
            next unless line_regex.match?(line)

            parsed_image_line = line_regex.match(line).named_captures
            if parsed_image_line["registry"] == "docker.io"
              parsed_image_line["registry"] = nil
            end

            version = version_from(parsed_image_line)
            next unless version

            dependency_set << Dependency.new(
              name: parsed_image_line.fetch("image"),
              version: version,
              package_manager: "docker",
              requirements: [
                requirement: nil,
                groups: [],
                file: docker_file.name,
                source: source_from(parsed_image_line)
              ]
            )
          end
        end
      end

      def dockerfiles
        dependency_files.select { |f| f.name.match?(/dockerfile/i) }
      end

      def drone_files
        dependency_files.select { |f| f.name.match?(/.drone.yml/i) }
      end

      def version_from(parsed_line)
        return parsed_line.fetch("tag") if parsed_line.fetch("tag")

        version_from_digest(
          registry: parsed_line.fetch("registry"),
          image: parsed_line.fetch("image"),
          digest: parsed_line.fetch("digest")
        )
      end

      def source_from(parsed_line)
        source = {}

        if parsed_line.fetch("registry")
          source[:registry] = parsed_line.fetch("registry")
        end

        source[:tag] = parsed_line.fetch("tag") if parsed_line.fetch("tag")

        if parsed_line.fetch("digest")
          source[:digest] = parsed_line.fetch("digest")
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

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Dockerfile or .drone.yml!"
      end
    end
  end
end

Dependabot::FileParsers.register("docker", Dependabot::Docker::FileParser)

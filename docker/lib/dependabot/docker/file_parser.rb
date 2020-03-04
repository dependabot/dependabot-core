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
      require "yaml"

      # Detials of Docker regular expressions is at
      # https://github.com/docker/distribution/blob/master/reference/regexp.go
      DOMAIN_COMPONENT =
        /(?:[a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])/.freeze
      DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/.freeze
      REGISTRY = /(?<registry>#{DOMAIN}(?::[0-9]+)?)/.freeze

      NAME_COMPONENT = /(?:[a-z0-9]+(?:(?:[._]|__|[-]*)[a-z0-9]+)*)/.freeze
      IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}.freeze

      FROM = /[Ff][Rr][Oo][Mm]/.freeze
      TAG = /:(?<tag>[\w][\w.-]{0,127})/.freeze
      DIGEST = /@(?<digest>[^\s]+)/.freeze
      NAME = /\s+AS\s+(?<name>[a-zA-Z0-9_-]+)/.freeze
      FROM_LINE =
        %r{^#{FROM}\s+(#{REGISTRY}/)?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?}.freeze

      AWS_ECR_URL = /dkr\.ecr\.(?<region>[^.]+).amazonaws\.com/.freeze

      LINE =
        %r{^(#{REGISTRY}/)?#{IMAGE}#{TAG}?}.freeze

      def parse
        dependency_set = DependencySet.new
        input_files.each do |file|
          parsed = begin
            YAML.safe_load(file.content, [], [], true)
                   rescue ArgumentError => e
                     puts "Could not parse YAML: #{e.message}"
          end

          res = parsed["resources"]
          res.each do |item|
            next unless (item["type"] == "registry-image") && (item["source"]["tag"] != "latest")

            parsed_data = item["source"]["repository"].to_s + ":" + item["source"]["tag"].to_s
            img_data = LINE.match(parsed_data).named_captures

            version = version_from(img_data)
            next unless version

            add_dependency_set(dependency_set,
                               img_data.fetch("image"),
                               version,
                               source_from(img_data),
                               file.name)
          end
        end

        dependency_set.dependencies
      end

      private

      def input_files
        # The Docker file fetcher only fetches Dockerfiles, so no need to
        # filter here
        dependency_files
      end

      def version_from(parsed_from_line)
        return parsed_from_line.fetch("tag") if parsed_from_line.fetch("tag")

        version_from_digest(
          registry: parsed_from_line.fetch("registry"),
          image: parsed_from_line.fetch("image"),
          digest: parsed_from_line.fetch("digest")
        )
      end

      def source_from(img_data)
        source = {}

        if img_data.fetch("registry")
          source[:registry] = img_data.fetch("registry")
        end
        if img_data.fetch("tag")
        source[:tag] = img_data.fetch("tag")
        end

        source
      end

      def version_from(img_data)
        return img_data.fetch("tag") if img_data.fetch("tag")
      end

      def check_required_files
        return if dependency_files.any?

        raise "No file!"
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

      def add_dependency_set(dependency_set, name_in, version_in, source_in, file_in)
        dependency_set << Dependency.new(
          name: name_in,
          version: version_in,
          package_manager: "docker",
          requirements: [
            requirement: nil,
            groups: [],
            file: file_in,
            source: source_in
          ]
        )
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

        raise "No Dockerfile!"
      end
    end
  end
end

Dependabot::FileParsers.register("docker", Dependabot::Docker::FileParser)

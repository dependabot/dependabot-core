# frozen_string_literal: true

require "docker_registry2"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Docker
      class Docker < Dependabot::FileParsers::Base
        # Detials of Docker regular expressions is at
        # https://github.com/docker/distribution/blob/master/reference/regexp.go
        DOMAIN_COMPONENT = /(?:[a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])/
        DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/
        REGISTRY = %r{(?<registry>#{DOMAIN}(?::[0-9]+)?)/}

        NAME_COMPONENT = /(?:[a-z0-9]+(?:(?:[._]|__|[-]*)[a-z0-9]+)*)/
        IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}

        FROM = /[Ff][Rr][Oo][Mm]/
        TAG = /:(?<tag>[\w][\w.-]{0,127})/
        DIGEST = /@(?<digest>[^\s]+)/
        NAME = /\s+AS\s+(?<name>[a-zA-Z0-9_-]+)/
        FROM_LINE = /^#{FROM}\s+#{REGISTRY}?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?/

        def parse
          dependencies = []

          dockerfile.content.each_line do |line|
            next unless FROM_LINE.match?(line)
            parsed_from_line = FROM_LINE.match(line).named_captures

            check_registry(parsed_from_line)

            version = version_from(parsed_from_line)
            next unless version

            dependencies << Dependency.new(
              name: parsed_from_line.fetch("image"),
              version: version,
              package_manager: "docker",
              requirements: [
                requirement: nil,
                groups: [],
                file: dockerfile.name,
                source: {
                  type: parsed_from_line.fetch("digest") ? "digest" : "tag"
                }
              ]
            )
          end

          dependencies
        end

        private

        def dockerfile
          @dockerfile ||= get_original_file("Dockerfile")
        end

        def check_registry(parsed_from_line)
          return unless parsed_from_line.fetch("registry")
          raise PrivateSourceNotReachable, parsed_from_line.fetch("registry")
        end

        def version_from(parsed_from_line)
          return parsed_from_line.fetch("tag") if parsed_from_line.fetch("tag")
          version_from_digest(
            image: parsed_from_line.fetch("image"),
            digest: parsed_from_line.fetch("digest")
          )
        end

        def version_from_digest(image:, digest:)
          return unless digest

          repo = image.split("/").count < 2 ? "library/#{image}" : image
          registry = DockerRegistry2.connect

          registry.tags(repo).fetch("tags").find do |tag|
            begin
              head = registry.dohead "/v2/#{repo}/manifests/#{tag}"
              head.headers[:docker_content_digest] == digest
            rescue RestClient::NotFound
              # Shouldn't happen, but it does. Example of existing tag with
              # no manifest is "library/python", "2-windowsservercore".
              false
            end
          end
        end

        def check_required_files
          %w(Dockerfile).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end
      end
    end
  end
end

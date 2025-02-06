# typed: true
# frozen_string_literal: true

require "yaml"

require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/common/file_parser_helper"

module Dependabot
  module DockerCompose
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      include Dependabot::Docker::FileParserHelper

      # Details of Docker regular expressions is at
      # https://github.com/docker/distribution/blob/master/reference/regexp.go
      DOMAIN_COMPONENT =
        /(?:[[:alnum:]]|[[:alnum:]][[[:alnum:]]-]*[[:alnum:]])/
      DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/
      REGISTRY = /(?<registry>#{DOMAIN}(?::\d+)?)/

      NAME_COMPONENT = /(?:[a-z\d]+(?:(?:[._]|__|[-]*)[a-z\d]+)*)/
      IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}

      TAG = /:(?<tag>[\w][\w.-]{0,127})/
      DIGEST = /@(?<digest>[^\s]+)/
      NAME = /\s+AS\s+(?<name>[\w-]+)/
      FROM_IMAGE = %r{^(?:#{REGISTRY}/)?#{IMAGE}(?:#{TAG})?(?:#{DIGEST})?(?:#{NAME})?}

      def parse
        dependency_set = DependencySet.new

        composefiles.each do |composefile|
          yaml = YAML.safe_load(composefile.content)
          yaml["services"].each do |_, service|
            parsed_from_image =
              FROM_IMAGE.match(service["image"]).named_captures
            parsed_from_image["registry"] = nil if parsed_from_image["registry"] == "docker.io"

            version = version_from(parsed_from_image)
            next unless version

            dependency_set << Dependency.new(
              name: parsed_from_image["image"],
              version: version,
              package_manager: "docker_compose",
              requirements: [
                requirement: nil,
                groups: [],
                file: composefile.name,
                source: source_from(parsed_from_image)
              ]
            )
          end
        end

        dependency_set.dependencies
      end

      private

      def composefiles
        # The DockerCompose file fetcher only fetches docker-compose.yml files,
        # so no need to filter here
        dependency_files
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No docker-compose.yml file!"
      end
    end
  end
end

Dependabot::FileParsers.register(
  "docker_compose",
  Dependabot::DockerCompose::FileParser
)

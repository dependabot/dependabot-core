# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/errors"
require 'dependabot/docker/utils/dockerfile_parser'

module Dependabot
  module Docker
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

      def parse
        dependency_set = DependencySet.new

        dockerfiles.each do |dockerfile|
          dockerfile.content.each_line do |line|
            next unless Utils::DockerFileParser::FROM_LINE.match?(line)

            docker_file_parser = Utils::DockerFileParser.new(line, credentials)

            version = docker_file_parser.version
            next unless version

            dependency_set << Dependency.new(
              name: docker_file_parser.image,
              version: version,
              package_manager: "docker",
              requirements: [
                requirement: nil,
                groups: [],
                file: dockerfile.name,
                source: docker_file_parser.source
              ]
            )
          end
        end

        dependency_set.dependencies
      end

      private

      def dockerfiles
        # The Docker file fetcher only fetches Dockerfiles, so no need to
        # filter here
        dependency_files
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

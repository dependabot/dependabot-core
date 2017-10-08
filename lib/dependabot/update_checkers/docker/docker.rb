# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "docker_registry2"

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

          # TODO: How can we get details to connect to private registries?
          registry = DockerRegistry2.connect

          tags =
            if dependency.name.split("/").count < 2
              registry.tags("library/#{dependency.name}")
            else
              registry.tags(dependency.name)
            end

          tags.fetch("tags").
            select { |tag| tag.match?(VERSION_REGEX) }.
            map { |tag| Gem::Version.new(tag) }.
            max
        end
      end
    end
  end
end

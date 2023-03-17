# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module Docker
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        return if dependency.requirements.empty?

        new_source = dependency.requirements.first[:source]
        return unless new_source && new_source[:registry] && new_source[:tag]

        image_ref = "#{new_source[:registry]}/#{dependency.name}:#{new_source[:tag]}"
        image_details_output = SharedHelpers.run_shell_command("regctl image inspect #{image_ref}")
        image_details = JSON.parse(image_details_output)
        image_source = image_details.dig("config", "Labels", "org.opencontainers.image.source")
        return unless image_source

        Dependabot::Source.from_url(image_source)
      rescue StandardError => e
        Dependabot.logger.warn("Error looking up Docker source: #{e.message}")
        nil
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("docker", Dependabot::Docker::MetadataFinder)

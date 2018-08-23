# frozen_string_literal: true

require "excon"
require "json"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    module Terraform
      class Terraform < Dependabot::MetadataFinders::Base
        private

        def look_up_source
          case new_source_type
          when "git" then find_source_from_git_url
          when "registry" then find_source_from_registry_details
          else raise "Unexpected source type: #{new_source_type}"
          end
        end

        def new_source_type
          sources =
            dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

          return "default" if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1
          sources.first[:type] || sources.first.fetch("type")
        end

        def find_source_from_git_url
          info = dependency.requirements.map { |r| r[:source] }.compact.first

          url = info[:url] || info.fetch("url")
          Source.from_url(url)
        end

        def find_source_from_registry_details
          info = dependency.requirements.map { |r| r[:source] }.compact.first

          hostname = info[:registry_hostname] || info["registry_hostname"]

          # TODO: Implement service discovery for custom registries
          return unless hostname == "registry.terraform.io"

          url = "https://registry.terraform.io/v1/modules/"\
                "#{dependency.name}/#{dependency.version}"

          response = Excon.get(
            url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          unless response.status == 200
            raise "Response from registry was #{response.status}"
          end

          source_url = JSON.parse(response.body).fetch("source")
          Source.from_url(source_url) if source_url
        end
      end
    end
  end
end

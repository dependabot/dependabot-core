# frozen_string_literal: true

# TODO: File and specs need to be updated

require "excon"
require "json"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Pub
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        case new_source_type
        when "git" then find_source_from_git_url
        when "hosted" then find_source_from_hosted_details
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

      # Hosted Pub Repository API docs:
      # https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md
      def find_source_from_hosted_details
        info = dependency.requirements.map { |r| r[:source] }.compact.first

        hostname = info[:url] || info["url"]

        url = "#{hostname}/api/packages/"\
              "#{dependency.name}"

        response = Excon.get(
          url,
          idempotent: true,
          **SharedHelpers.excon_defaults(
            {
              headers: {
                accept: "application/vnd.pub.v2+json",
                "X-Pub-Environment": "dependabot"
                # TODO: Condier adding X-Pub-Headers (https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md)
              }
            }
          )
        )

        raise "Response from hosted pub repository was #{response.status}" unless response.status == 200

        latest_version = JSON.parse(response.body).fetch("latest", nil)
        pubspec = latest_version.fetch("pubspec", nil) if latest_version
        repository = pubspec.fetch("repository", nil) if pubspec
        homepage = pubspec.fetch("homepage", nil) if pubspec

        return Source.from_url(repository) if repository
        return Source.from_url(homepage) if homepage
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("pub", Dependabot::Pub::MetadataFinder)
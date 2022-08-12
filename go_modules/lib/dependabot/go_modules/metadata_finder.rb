# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/go_modules/path_converter"

module Dependabot
  module GoModules
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        return look_up_git_dependency_source if git_dependency?

        path_str = (specified_source_string || dependency.name)
        url = Dependabot::GoModules::PathConverter.git_url_for_path(path_str)
        Source.from_url(url) if url
      end

      def git_dependency?
        return false unless declared_source_details

        dependency_type =
          declared_source_details.fetch(:type, nil) ||
          declared_source_details.fetch("type")

        dependency_type == "git"
      end

      def look_up_git_dependency_source
        specified_url =
          declared_source_details.fetch(:url, nil) ||
          declared_source_details.fetch("url")

        Source.from_url(specified_url)
      end

      def specified_source_string
        declared_source_details&.fetch(:source, nil) ||
          declared_source_details&.fetch("source", nil)
      end

      def declared_source_details
        sources = dependency.requirements.
                  map { |r| r.fetch(:source) }.
                  uniq.compact

        raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

        sources.first
      end
    end
  end
end

Dependabot::MetadataFinders.
  register("go_modules", Dependabot::GoModules::MetadataFinder)

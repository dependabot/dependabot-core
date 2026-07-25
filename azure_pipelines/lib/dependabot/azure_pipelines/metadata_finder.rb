# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

require "dependabot/azure_pipelines/constants"
require "dependabot/azure_pipelines/package/package_details_fetcher"

module Dependabot
  module AzurePipelines
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      # Tasks do not have per-task repositories or changelogs, so the best we can offer
      # is the directory in the repository Microsoft develops the task in.
      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        directory = task_directory
        return nil unless directory

        Dependabot::Source.new(
          provider: "github",
          repo: TASKS_REPO,
          directory: "#{TASKS_DIRECTORY}/#{directory}"
        )
      end

      sig { returns(T.nilable(String)) }
      def task_directory
        Package::PackageDetailsFetcher.new(
          dependency: dependency,
          credentials: credentials
        ).task_directory
      end
    end
  end
end

Dependabot::MetadataFinders.register("azure_pipelines", Dependabot::AzurePipelines::MetadataFinder)

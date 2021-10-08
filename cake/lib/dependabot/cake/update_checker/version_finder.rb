# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/nuget/update_checker/version_finder"

module Dependabot
  module Cake
    class UpdateChecker
      class VersionFinder < Dependabot::Nuget::UpdateChecker::VersionFinder
        require_relative "repository_finder"

        private

        def dependency_urls
          @dependency_urls ||=
            RepositoryFinder.new(
              dependency: dependency,
              credentials: credentials,
              config_files: nuget_configs,
              cake_config: cake_config
            ).dependency_urls
        end

        def cake_config
          @cake_config ||=
            dependency_files.find { |f| f.name == "cake.config" }
        end
      end
    end
  end
end

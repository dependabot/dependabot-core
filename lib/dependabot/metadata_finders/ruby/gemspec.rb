# frozen_string_literal: true
require "dependabot/metadata_finders/ruby/bundler"

module Dependabot
  module MetadataFinders
    module Ruby
      # Inherit from MetadataFinder::Ruby::Bundler
      class Gemspec < Dependabot::MetadataFinders::Ruby::Bundler
        def initialize(dependency:, github_client:)
          super

          # Update the dependency version to be the latest version. On the
          # original dependency it will have been a requirement string.
          @dependency = Dependency.new(
            name: @dependency.name,
            package_manager: @dependency.package_manager,
            previous_version: @dependency.previous_version,
            version: latest_version
          )
        end

        def latest_version
          Gems.info(dependency.name)["version"]
        end
      end
    end
  end
end

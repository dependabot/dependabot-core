# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven < Dependabot::UpdateCheckers::Base
        require_relative "maven/requirements_updater"
        require_relative "maven/version"

        def latest_version
          version_class.new(maven_central_latest_version)
        end

        def latest_resolvable_version
          # TODO: Resolve the pom.xml to find the latest version we could update
          # to without updating any other dependencies at the same time
          #
          # The above is hard. Currently we just return the latest version and
          # hope (hence this package manager is in beta!)
          latest_version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s
          ).updated_requirements
        end

        def version_class
          Maven::Version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Yarn (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def maven_central_latest_version
          maven_central_dependency_metadata.at_css("release")&.content
        end

        def maven_central_dependency_metadata
          @maven_central_dependency_metadata ||=
            begin
              response = Excon.get(
                "#{maven_central_dependency_url}maven-metadata.xml",
                idempotent: true,
                middlewares: SharedHelpers.excon_middleware
              )
              Nokogiri::XML(response.body)
            end
        end

        def maven_central_dependency_url
          "https://search.maven.org/remotecontent?filepath="\
          "#{dependency.name.gsub(/[:.]/, '/')}/"
        end
      end
    end
  end
end

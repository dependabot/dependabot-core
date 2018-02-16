# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/java/maven"
require "dependabot/update_checkers/java/maven/version"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven
        class VersionFinder
          def initialize(dependency:)
            @dependency = dependency
          end

          def latest_release
            return if maven_central_latest_version.nil?
            Maven::Version.new(maven_central_latest_version)
          end

          def versions
            maven_central_dependency_metadata.
              css("versions > version").
              select { |node| Maven::Version.correct?(node.content) }.
              map { |node| Maven::Version.new(node.content) }.sort
          end

          private

          attr_reader :dependency

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
end

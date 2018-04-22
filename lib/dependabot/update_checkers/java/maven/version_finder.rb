# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/java/maven"
require "dependabot/utils/java/version"

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
            Utils::Java::Version.new(maven_central_latest_version)
          end

          def versions
            maven_central_dependency_metadata.
              css("versions > version").
              select { |node| Utils::Java::Version.correct?(node.content) }.
              map { |node| Utils::Java::Version.new(node.content) }.sort
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
                  maven_central_dependency_metadata_url,
                  idempotent: true,
                  middlewares: SharedHelpers.excon_middleware
                )
                Nokogiri::XML(response.body)
              end
          end

          def maven_central_dependency_metadata_url
            group_id, artifact_id = dependency.name.split(":")
            "https://repo.maven.apache.org/maven2/"\
            "#{group_id.tr('.', '/')}/#{artifact_id}/maven-metadata.xml"
          end
        end
      end
    end
  end
end

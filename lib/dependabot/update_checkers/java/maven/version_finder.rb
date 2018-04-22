# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/file_parsers/java/maven/repositories_finder"
require "dependabot/update_checkers/java/maven"
require "dependabot/utils/java/version"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven
        class VersionFinder
          def initialize(dependency:, dependency_files:)
            @dependency = dependency
            @dependency_files = dependency_files
          end

          def latest_release
            return if maven_central_latest_version.nil?
            Utils::Java::Version.new(maven_central_latest_version)
          end

          def versions
            repository_urls.
              map { |url| dependency_metadata(url).css("versions > version") }.
              flatten.
              select { |node| Utils::Java::Version.correct?(node.content) }.
              map { |node| Utils::Java::Version.new(node.content) }.sort
          end

          private

          attr_reader :dependency, :dependency_files

          def maven_central_latest_version
            repository_urls.
              map { |url| dependency_metadata(url).at_css("release")&.content }.
              max_by do |v|
                if Utils::Java::Version.correct?(v)
                  Utils::Java::Version.new(v)
                else
                  Utils::Java::Version.new("0")
                end
              end
          end

          def dependency_metadata(repository_url)
            @dependency_metadata ||= {}
            @dependency_metadata[repository_url] ||=
              begin
                response = Excon.get(
                  dependency_metadata_url(repository_url),
                  idempotent: true,
                  middlewares: SharedHelpers.excon_middleware
                )
                Nokogiri::XML(response.body)
              end
          end

          def repository_urls
            @repository_urls ||=
              FileParsers::Java::Maven::RepositoriesFinder.new(
                dependency_files: dependency_files
              ).repository_urls(pom: pom)
          end

          def pom
            filename = dependency.requirements.first.fetch(:file)
            dependency_files.find { |f| f.name == filename }
          end

          def dependency_metadata_url(repository_url)
            group_id, artifact_id = dependency.name.split(":")

            "#{repository_url}/"\
            "#{group_id.tr('.', '/')}/"\
            "#{artifact_id}/"\
            "maven-metadata.xml"
          end
        end
      end
    end
  end
end

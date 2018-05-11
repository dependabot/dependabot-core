# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/file_parsers/java/gradle/repositories_finder"
require "dependabot/update_checkers/java/gradle"
require "dependabot/utils/java/version"

module Dependabot
  module UpdateCheckers
    module Java
      class Gradle
        class VersionFinder
          GOOGLE_MAVEN_REPO = "https://maven.google.com"

          def initialize(dependency:, dependency_files:)
            @dependency = dependency
            @dependency_files = dependency_files
          end

          def latest_version_details
            possible_versions = versions

            unless wants_prerelease?
              possible_versions =
                possible_versions.
                reject { |v| v.fetch(:version).prerelease? }
            end

            unless wants_date_based_version?
              possible_versions =
                possible_versions.
                reject { |v| v.fetch(:version) > version_class.new(1900) }
            end

            possible_versions.last
          end

          def versions
            version_details =
              repository_urls.map do |url|
                next google_version_details if url == GOOGLE_MAVEN_REPO
                dependency_metadata(url).css("versions > version").
                  select { |node| version_class.correct?(node.content) }.
                  map { |node| version_class.new(node.content) }.
                  map { |version| { version: version, source_url: url } }
              end.flatten

            version_details.sort_by { |details| details.fetch(:version) }
          end

          private

          attr_reader :dependency, :dependency_files

          def wants_prerelease?
            return false unless dependency.version
            return false unless version_class.correct?(dependency.version)
            version_class.new(dependency.version).prerelease?
          end

          def wants_date_based_version?
            return false unless dependency.version
            return false unless version_class.correct?(dependency.version)
            version_class.new(dependency.version) >= version_class.new(100)
          end

          def google_version_details
            url = GOOGLE_MAVEN_REPO
            group_id, artifact_id = dependency.name.split(":")

            dependency_metadata_url = "#{GOOGLE_MAVEN_REPO}/"\
                                      "#{group_id.tr('.', '/')}/"\
                                      "group-index.xml"

            @google_version_details ||=
              begin
                response = Excon.get(
                  dependency_metadata_url,
                  idempotent: true,
                  omit_default_port: true,
                  middlewares: SharedHelpers.excon_middleware
                )
                Nokogiri::XML(response.body)
              end

            xpath = "/#{group_id}/#{artifact_id}"
            return unless @google_version_details.at_xpath(xpath)
            @google_version_details.at_xpath(xpath).
              attributes.fetch("versions").
              value.split(",").
              select { |v| version_class.correct?(v) }.
              map { |v| version_class.new(v) }.
              map { |version| { version: version, source_url: url } }
          end

          def dependency_metadata(repository_url)
            @dependency_metadata ||= {}
            @dependency_metadata[repository_url] ||=
              begin
                response = Excon.get(
                  dependency_metadata_url(repository_url),
                  idempotent: true,
                  omit_default_port: true,
                  middlewares: SharedHelpers.excon_middleware
                )
                Nokogiri::XML(response.body)
              rescue Excon::Error::Socket, Excon::Error::Timeout
                namespace = FileParsers::Java::Gradle::RepositoriesFinder
                central = namespace::CENTRAL_REPO_URL
                raise if repository_url == central
                Nokogiri::XML("")
              end
          end

          def repository_urls
            @repository_urls ||=
              FileParsers::Java::Gradle::RepositoriesFinder.new(
                dependency_files: dependency_files
              ).repository_urls
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

          def version_class
            Utils::Java::Version
          end
        end
      end
    end
  end
end

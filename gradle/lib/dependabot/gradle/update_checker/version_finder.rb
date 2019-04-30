# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/gradle/file_parser/repositories_finder"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/version"
require "dependabot/gradle/requirement"

module Dependabot
  module Gradle
    class UpdateChecker
      class VersionFinder
        GOOGLE_MAVEN_REPO = "https://maven.google.com"
        GRADLE_PLUGINS_REPO = "https://plugins.gradle.org/m2"
        TYPE_SUFFICES = %w(jre android java).freeze

        def initialize(dependency:, dependency_files:, ignored_versions:,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
        end

        def latest_version_details
          possible_versions = versions

          possible_versions = filter_prereleases(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)

          possible_versions.last
        end

        def lowest_security_fix_version_details
          possible_versions = versions

          possible_versions = filter_prereleases(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)
          possible_versions = filter_vulnerable_versions(possible_versions)
          possible_versions = filter_lower_versions(possible_versions)

          possible_versions.first
        end

        def versions
          version_details =
            repository_urls.map do |url|
              next google_version_details if url == GOOGLE_MAVEN_REPO

              dependency_metadata(url).css("versions > version").
                select { |node| version_class.correct?(node.content) }.
                map { |node| version_class.new(node.content) }.
                map { |version| { version: version, source_url: url } }
            end.flatten.compact

          version_details.sort_by { |details| details.fetch(:version) }
        end

        private

        attr_reader :dependency, :dependency_files, :ignored_versions,
                    :security_advisories

        def filter_prereleases(possible_versions)
          return possible_versions if wants_prerelease?

          possible_versions.reject { |v| v.fetch(:version).prerelease? }
        end

        def filter_date_based_versions(possible_versions)
          return possible_versions if wants_date_based_version?

          possible_versions.
            reject { |v| v.fetch(:version) > version_class.new(1900) }
        end

        def filter_version_types(possible_versions)
          possible_versions.
            select { |v| matches_dependency_version_type?(v.fetch(:version)) }
        end

        def filter_ignored_versions(possible_versions)
          versions_array = possible_versions

          ignored_versions.each do |req|
            ignore_req = Gradle::Requirement.new(req.split(","))
            versions_array =
              versions_array.
              reject { |v| ignore_req.satisfied_by?(v.fetch(:version)) }
          end

          versions_array
        end

        def filter_vulnerable_versions(possible_versions)
          versions_array = possible_versions

          security_advisories.each do |advisory|
            versions_array =
              versions_array.
              reject { |v| advisory.vulnerable?(v.fetch(:version)) }
          end

          versions_array
        end

        def filter_lower_versions(possible_versions)
          possible_versions.select do |v|
            v.fetch(:version) > version_class.new(dependency.version)
          end
        end

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
                **SharedHelpers.excon_defaults
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
                **SharedHelpers.excon_defaults
              )
              Nokogiri::XML(response.body)
            rescue Excon::Error::Socket, Excon::Error::Timeout
              namespace = Gradle::FileParser::RepositoriesFinder
              central = namespace::CENTRAL_REPO_URL
              raise if repository_url == central

              Nokogiri::XML("")
            end
        end

        def repository_urls
          plugin? ? plugin_repository_urls : dependency_repository_urls
        end

        def dependency_repository_urls
          requirement_files =
            dependency.requirements.
            map { |r| r.fetch(:file) }.
            map { |nm| dependency_files.find { |f| f.name == nm } }

          @dependency_repository_urls ||=
            requirement_files.flat_map do |target_file|
              Gradle::FileParser::RepositoriesFinder.new(
                dependency_files: dependency_files,
                target_dependency_file: target_file
              ).repository_urls
            end.uniq
        end

        def plugin_repository_urls
          [GRADLE_PLUGINS_REPO] + dependency_repository_urls
        end

        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type =
            TYPE_SUFFICES.
            find { |t| dependency.version.split(/[.\-]/).include?(t) }

          version_type =
            TYPE_SUFFICES.
            find { |t| comparison_version.to_s.split(/[.\-]/).include?(t) }

          current_type == version_type
        end

        def pom
          filename = dependency.requirements.first.fetch(:file)
          dependency_files.find { |f| f.name == filename }
        end

        def dependency_metadata_url(repository_url)
          group_id, artifact_id =
            if plugin?
              [dependency.name, "#{dependency.name}.gradle.plugin"]
            else
              dependency.name.split(":")
            end

          "#{repository_url}/"\
          "#{group_id.tr('.', '/')}/"\
          "#{artifact_id}/"\
          "maven-metadata.xml"
        end

        def plugin?
          dependency.requirements.any? { |r| r.fetch(:groups) == ["plugins"] }
        end

        def version_class
          Gradle::Version
        end
      end
    end
  end
end

# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileParser
      class RepositoriesFinder
        extend T::Sig

        SUPPORTED_BUILD_FILE_NAMES = %w(build.gradle build.gradle.kts).freeze
        SUPPORTED_SETTINGS_FILE_NAMES = %w(settings.gradle settings.gradle.kts).freeze

        # The Central Repo doesn't have special status for Gradle, but until
        # we're confident we're selecting repos correctly it's wise to include
        # it as a default.
        CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"
        GOOGLE_MAVEN_REPO = "https://maven.google.com"
        GRADLE_PLUGINS_REPO = "https://plugins.gradle.org/m2"

        REPOSITORIES_BLOCK_START = /(?:^|\s)repositories\s*\{/

        GROOVY_MAVEN_REPO_REGEX = /maven\s*\{[^\}]*\surl[\s\(]=?[^'"]*['"](?<url>[^'"]+)['"]/

        KOTLIN_MAVEN_REPO_REGEX = /maven\((url\s?\=\s?)?["](?<url>[^"]+)["]\)/

        MAVEN_REPO_REGEX = /(#{KOTLIN_MAVEN_REPO_REGEX}|#{GROOVY_MAVEN_REPO_REGEX})/

        def initialize(dependency_files:, target_dependency_file:)
          @dependency_files = dependency_files
          @target_dependency_file = target_dependency_file
          raise "No target file!" unless target_dependency_file
        end

        def repository_urls
          repository_urls = []
          repository_urls += inherited_repository_urls(top_level_buildfile)
          FileParser.find_includes(top_level_buildfile, dependency_files).each do |dependency_file|
            repository_urls += inherited_repository_urls(dependency_file)
          end
          repository_urls += own_buildfile_repository_urls
          repository_urls += settings_file_repository_urls(top_level_settings_file)
          repository_urls = repository_urls.uniq

          return repository_urls unless repository_urls.empty?

          [CENTRAL_REPO_URL]
        end

        private

        attr_reader :dependency_files
        attr_reader :target_dependency_file

        def inherited_repository_urls(dependency_file)
          return [] unless dependency_file

          buildfile_content = comment_free_content(dependency_file)
          subproject_blocks = []

          buildfile_content.scan(/(?:^|\s)allprojects\s*\{/) do
            mtch = T.must(Regexp.last_match)
            subproject_blocks <<
              mtch.post_match[0..closing_bracket_index(mtch.post_match)]
          end

          if top_level_buildfile != target_dependency_file
            buildfile_content.scan(/(?:^|\s)subprojects\s*\{/) do
              mtch = T.must(Regexp.last_match)
              subproject_blocks <<
                mtch.post_match[0..closing_bracket_index(mtch.post_match)]
            end
          end

          repository_urls_from(subproject_blocks.join("\n"))
        end

        def own_buildfile_repository_urls
          return [] unless top_level_buildfile

          buildfile_content = comment_free_content(top_level_buildfile)

          own_buildfile_urls = []

          subproject_buildfile_content = buildfile_content.dup.scan(/(?:^|\s)subprojects\s*\{/) do
            mtch = T.must(Regexp.last_match)
            buildfile_content.gsub(
              mtch.post_match[0..closing_bracket_index(mtch.post_match)],
              ""
            )
          end

          own_buildfile_urls += repository_urls_from(buildfile_content)
          own_buildfile_urls += repository_urls_from(subproject_buildfile_content)
          own_buildfile_urls
        end

        def settings_file_repository_urls(settings_file)
          return [] unless settings_file

          settings_file_content = comment_free_content(settings_file)
          dependency_resolution_management_repositories = []

          settings_file_content.scan(/(?:^|\s)dependencyResolutionManagement\s*\{/) do
            mtch = T.must(Regexp.last_match)
            dependency_resolution_management_repositories <<
              mtch.post_match[0..closing_bracket_index(mtch.post_match)]
          end

          repository_urls_from(dependency_resolution_management_repositories.join("\n"))
        end

        def repository_urls_from(buildfile_content)
          repository_urls = []

          repository_blocks = []
          buildfile_content.scan(REPOSITORIES_BLOCK_START) do
            mtch = T.must(Regexp.last_match)
            repository_blocks <<
              mtch.post_match[0..closing_bracket_index(mtch.post_match)]
          end

          repository_blocks.each do |block|
            repository_urls << GOOGLE_MAVEN_REPO if block.match?(/\sgoogle\(/)

            repository_urls << CENTRAL_REPO_URL if block.match?(/\smavenCentral\(/)

            repository_urls << "https://jcenter.bintray.com/" if block.match?(/\sjcenter\(/)

            repository_urls << GRADLE_PLUGINS_REPO if block.match?(/\sgradlePluginPortal\(/)

            block.scan(MAVEN_REPO_REGEX) do
              repository_urls << T.must(Regexp.last_match).named_captures.fetch("url")
            end
          end

          repository_urls
            .map { |url| url.strip.gsub(%r{/$}, "") }
            .select { |url| valid_url?(url) }
            .uniq
        end

        def closing_bracket_index(string)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == "{"
            closes_required -= 1 if char == "}"
            return index if closes_required.zero?
          end

          0
        end

        def valid_url?(url)
          # Reject non-http URLs because they're probably parsing mistakes
          return false unless url.start_with?("http")

          URI.parse(url)
          true
        rescue URI::InvalidURIError
          false
        end

        def comment_free_content(buildfile)
          buildfile.content
                   .gsub(%r{(?<=^|\s)//.*$}, "\n")
                   .gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
        end

        def top_level_buildfile
          @top_level_buildfile ||= dependency_files.find do |f|
            SUPPORTED_BUILD_FILE_NAMES.include?(f.name)
          end
        end

        def top_level_settings_file
          @top_level_settings_file ||= dependency_files.find do |f|
            SUPPORTED_SETTINGS_FILE_NAMES.include?(f.name)
          end
        end
      end
    end
  end
end

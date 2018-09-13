# frozen_string_literal: true

require "dependabot/file_parsers/java/gradle"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Java
      class Gradle
        class RepositoriesFinder
          # The Central Repo doesn't have special status for Gradle, but until
          # we're confident we're selecting repos correctly it's wise to include
          # it as a default.
          CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"

          REPOSITORIES_BLOCK_START = /(?:^|\s)repositories\s*\{/
          MAVEN_REPO_REGEX =
            /maven\s*\{[^\}]*\surl[\s\(]\s*['"](?<url>[^'"]+)['"]/

          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def repository_urls
            repository_urls =
              buildfile_repositories.
              map { |url| url.strip.gsub(%r{/$}, "") }.
              select { |url| valid_url?(url) }.
              uniq

            return repository_urls unless repository_urls.empty?

            [CENTRAL_REPO_URL]
          end

          private

          attr_reader :dependency_files

          def buildfile_repositories
            repositories = []

            repository_blocks = []
            comment_free_content(buildfile).scan(REPOSITORIES_BLOCK_START) do
              mtch = Regexp.last_match
              repository_blocks <<
                mtch.post_match[0..closing_bracket_index(mtch.post_match)]
            end

            repository_blocks.each do |block|
              if block.include?(" google(")
                repositories << "https://maven.google.com/"
              end

              if block.include?(" mavenCentral(")
                repositories << "https://repo.maven.apache.org/maven2/"
              end

              if block.include?(" jcenter(")
                repositories << "https://jcenter.bintray.com/"
              end

              block.scan(MAVEN_REPO_REGEX) do
                repositories << Regexp.last_match.named_captures.fetch("url")
              end
            end

            repositories.uniq
          end

          def closing_bracket_index(string)
            closes_required = 1

            string.chars.each_with_index do |char, index|
              closes_required += 1 if char == "{"
              closes_required -= 1 if char == "}"
              return index if closes_required.zero?
            end
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
            buildfile.content.
              gsub(%r{(?<=^|\s)//.*$}, "\n").
              gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
          end

          def buildfile
            @buildfile ||=
              dependency_files.find { |f| f.name == "build.gradle" }
          end
        end
      end
    end
  end
end

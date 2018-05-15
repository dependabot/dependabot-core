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
          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @credentials = credentials
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
              repositories.map do |repository_details|
                url = repository_details.fetch("url")
                dependency_metadata(repository_details).
                  css("versions > version").
                  select { |node| version_class.correct?(node.content) }.
                  map { |node| version_class.new(node.content) }.
                  map { |version| { version: version, source_url: url } }
              end.flatten

            version_details.sort_by { |details| details.fetch(:version) }
          end

          private

          attr_reader :dependency, :dependency_files, :credentials

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

          def dependency_metadata(repository_details)
            @dependency_metadata ||= {}
            @dependency_metadata[repository_details.fetch("url")] ||=
              begin
                response = Excon.get(
                  dependency_metadata_url(repository_details.fetch("url")),
                  user: repository_details.fetch("username"),
                  password: repository_details.fetch("password"),
                  idempotent: true,
                  omit_default_port: true,
                  middlewares: SharedHelpers.excon_middleware
                )
                Nokogiri::XML(response.body)
              rescue Excon::Error::Socket, Excon::Error::Timeout
                central =
                  FileParsers::Java::Maven::RepositoriesFinder::CENTRAL_REPO_URL
                raise if repository_details.fetch("url") == central
                Nokogiri::XML("")
              end
          end

          def repositories
            @repositories ||= pom_repository_details +
                              credentials_repository_details
          end

          def pom_repository_details
            @pom_repository_details ||=
              FileParsers::Java::Maven::RepositoriesFinder.
              new(dependency_files: dependency_files).
              repository_urls(pom: pom).
              map do |url|
                { "url" => url, "username" => nil, "password" => nil }
              end
          end

          def credentials_repository_details
            credentials.
              select { |cred| cred["type"] == "maven_repository" }.
              map do |cred|
                {
                  "url" => cred.fetch("url").gsub(%r{/+$}, ""),
                  "username" => cred.fetch("username"),
                  "password" => cred.fetch("password")
                }
              end
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

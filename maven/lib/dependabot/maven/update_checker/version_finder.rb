# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/update_checker"
require "dependabot/maven/version"
require "dependabot/maven/requirement"

module Dependabot
  module Maven
    class UpdateChecker
      class VersionFinder
        TYPE_SUFFICES = %w(jre android java).freeze

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:)
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
          @forbidden_urls   = []
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

          possible_versions =
            possible_versions.
            select { |v| matches_dependency_version_type?(v.fetch(:version)) }

          ignored_versions.each do |req|
            ignore_req = Maven::Requirement.new(req.split(","))
            possible_versions =
              possible_versions.
              reject { |v| ignore_req.satisfied_by?(v.fetch(:version)) }
          end

          possible_versions.reverse.find { |v| released?(v.fetch(:version)) }
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

          if version_details.none? && forbidden_urls.any?
            raise PrivateSourceAuthenticationFailure, forbidden_urls.first
          end

          version_details.sort_by { |details| details.fetch(:version) }
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :forbidden_urls

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

        def released?(version)
          repositories.any? do |repository_details|
            url = repository_details.fetch("url")
            response = Excon.get(
              dependency_files_url(url, version),
              user: repository_details.fetch("username"),
              password: repository_details.fetch("password"),
              idempotent: true,
              **SharedHelpers.excon_defaults
            )

            artifact_id = dependency.name.split(":").last
            type = dependency.requirements.first.
                   dig(:metadata, :packaging_type)
            response.body.include?("#{artifact_id}-#{version}.#{type}")
          rescue Excon::Error::Socket, Excon::Error::Timeout
            false
          end
        end

        def dependency_metadata(repository_details)
          @dependency_metadata ||= {}
          @dependency_metadata[repository_details.hash] ||=
            begin
              response = Excon.get(
                dependency_metadata_url(repository_details.fetch("url")),
                user: repository_details.fetch("username"),
                password: repository_details.fetch("password"),
                idempotent: true,
                **SharedHelpers.excon_defaults
              )
              check_response(response, repository_details.fetch("url"))
              Nokogiri::XML(response.body)
            rescue Excon::Error::Socket, Excon::Error::Timeout
              raise if central_repo_urls.include?(repository_details["url"])

              Nokogiri::XML("")
            end
        end

        def check_response(response, repository_url)
          return unless [401, 403].include?(response.status)
          return if @forbidden_urls.include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          @forbidden_urls << repository_url
        end

        def repositories
          return @repositories if @repositories

          details = pom_repository_details + credentials_repository_details

          @repositories =
            details.reject do |repo|
              next if repo["password"]

              # Reject this entry if an identical one with a password exists
              details.any? { |r| r["url"] == repo["url"] && r["password"] }
            end
        end

        def pom_repository_details
          @pom_repository_details ||=
            Maven::FileParser::RepositoriesFinder.
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
                "username" => cred.fetch("username", nil),
                "password" => cred.fetch("password", nil)
              }
            end
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
          group_id, artifact_id = dependency.name.split(":")

          "#{repository_url}/"\
          "#{group_id.tr('.', '/')}/"\
          "#{artifact_id}/"\
          "maven-metadata.xml"
        end

        def dependency_files_url(repository_url, version)
          group_id, artifact_id = dependency.name.split(":")

          "#{repository_url}/"\
          "#{group_id.tr('.', '/')}/"\
          "#{artifact_id}/"\
          "#{version}/"
        end

        def version_class
          Maven::Version
        end

        def central_repo_urls
          central_url_without_protocol =
            Maven::FileParser::RepositoriesFinder::CENTRAL_REPO_URL.
            gsub(%r{^.*://}, "")

          %w(http:// https://).map { |p| p + central_url_without_protocol }
        end
      end
    end
  end
end

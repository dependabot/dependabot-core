# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/maven/file_parser"
require "dependabot/registry_client"

module Dependabot
  module Maven
    class FileParser
      class PomFetcher
        extend T::Sig

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
          @poms = T.let({}, T::Hash[String, DependencyFile])
        end

        sig { returns(T::Hash[String, DependencyFile]) }
        def internal_dependency_poms
          return @internal_dependency_poms if @internal_dependency_poms

          @internal_dependency_poms = T.let({}, T.nilable(T::Hash[String, DependencyFile]))
          dependency_files.each do |pom|
            doc = Nokogiri::XML(pom.content)
            group_id = doc.at_css("project > groupId") ||
                       doc.at_css("project > parent > groupId")
            artifact_id = doc.at_css("project > artifactId")

            next unless group_id && artifact_id

            dependency_name = [
              group_id.content.strip,
              artifact_id.content.strip
            ].join(":")

            T.must(@internal_dependency_poms)[dependency_name] = pom
          end

          T.must(@internal_dependency_poms)
        end

        sig do
          params(
            group_id: String,
            artifact_id: String,
            version: String,
            urls_to_try: T::Array[String]
          ).returns(T.nilable(DependencyFile)) # Fix: Added closing parenthesis
        end
        def fetch_remote_parent_pom(group_id, artifact_id, version, urls_to_try)
          pom_id = "#{group_id}:#{artifact_id}:#{version}"
          return @poms[pom_id] if @poms.key?(pom_id)

          urls_to_try.each do |base_url|
            url =
              if version.include?("SNAPSHOT")
                fetch_snapshot_pom_url(group_id, artifact_id, version, base_url)
              else
                remote_pom_url(group_id, artifact_id, version, base_url)
              end
            next if url.nil?

            response = fetch(url)
            next unless response.status == 200
            next unless pom?(response.body)

            dependency_file = DependencyFile.new(
              name: "remote_pom.xml",
              content: response.body
            )

            @poms[pom_id] = dependency_file
            return dependency_file
          rescue Excon::Error::Socket, Excon::Error::Timeout,
                 Excon::Error::TooManyRedirects, URI::InvalidURIError
            nil
          end

          # If a parent POM couldn't be found, return `nil`
          nil
        end

        private

        sig { params(group_id: String, artifact_id: String, version: String, base_repo_url: String).returns(String) }
        def remote_pom_url(group_id, artifact_id, version, base_repo_url)
          "#{base_repo_url}/" \
            "#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/" \
            "#{artifact_id}-#{version}.pom"
        end

        sig do
          params(group_id: String, artifact_id: String, version: String, snapshot_version: String,
                 base_repo_url: String).returns(String)
        end
        def remote_pom_snapshot_url(group_id, artifact_id, version, snapshot_version, base_repo_url)
          "#{base_repo_url}/" \
            "#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/" \
            "#{artifact_id}-#{snapshot_version}.pom"
        end

        sig { params(group_id: String, artifact_id: String, version: String, base_repo_url: String).returns(String) }
        def remote_pom_snapshot_metadata_url(group_id, artifact_id, version, base_repo_url)
          "#{base_repo_url}/" \
            "#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/" \
            "maven-metadata.xml"
        end

        sig do
          params(group_id: String, artifact_id: String, version: String, base_url: String).returns(T.nilable(String))
        end
        def fetch_snapshot_pom_url(group_id, artifact_id, version, base_url)
          url = remote_pom_snapshot_metadata_url(group_id, artifact_id, version, base_url)
          response = fetch(url)
          return nil unless response.status == 200

          snapshot = Nokogiri::XML(response.body)
                             .css("snapshotVersion")
                             .find { |node| node.at_css("extension").content == "pom" }
                             &.at_css("value")
                             &.content
          return nil unless snapshot

          remote_pom_snapshot_url(group_id, artifact_id, version, snapshot, base_url)
        end

        sig { params(url: String).returns(Excon::Response) }
        def fetch(url)
          @maven_responses ||= T.let({}, T.nilable(T::Hash[String, Excon::Response]))
          @maven_responses[url] ||= Dependabot::RegistryClient.get(url: url, options: { retry_limit: 1 })
        end

        sig { params(content: String).returns(T::Boolean) }
        def pom?(content)
          !Nokogiri::XML(content).at_css("project > artifactId").nil?
        end

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/gradle/file_parser/repositories_finder"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/version"
require "dependabot/gradle/requirement"
require "dependabot/maven/utils/auth_headers_finder"
require "sorbet-runtime"
require "dependabot/gradle/metadata_finder"

module Dependabot
  module Gradle
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"
        KOTLIN_PLUGIN_REPO_PREFIX = "org.jetbrains.kotlin"
        TYPE_SUFFICES = %w(jre android java native_mt agp).freeze

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            forbidden_urls: T.nilable(T::Array[String])
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, forbidden_urls:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @forbidden_urls = forbidden_urls

          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @google_version_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @dependency_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[String])) }
        attr_reader :forbidden_urls

        # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
        sig do
          returns(T::Array[T::Hash[String, T.untyped]])
        end
        def fetch_available_versions
          T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])
          package_releases = T.let([], T::Array[T::Hash[String, T.untyped]])

          version_details =
            repositories.map do |repository_details|
              url = repository_details.fetch("url")

              next google_version_details if url == Gradle::FileParser::RepositoriesFinder::GOOGLE_MAVEN_REPO

              dependency_metadata(repository_details).css("versions > version")
                                                     .select { |node| version_class.correct?(node.content) }
                                                     .map { |node| version_class.new(node.content) }
                                                     .map do |version|
                { version: version, source_url: url }
              end
            end.flatten.compact

          version_details = version_details.sort_by { |details| details.fetch(:version) }
          release_date_info = release_details

          version_details.map do |info|
            version = info[:version]&.to_s

            package_releases << {
              version: Gradle::Version.new(version),
              released_at: release_date_info.none? ? nil : (release_date_info[version]&.fetch(:release_date) || nil),
              source_url: info[:source_url]
            }
          end
          if version_details.none? && T.must(forbidden_urls).any?
            raise PrivateSourceAuthenticationFailure,
                  T.must(forbidden_urls).first
          end
          # version_details

          package_releases
        end
        # rubocop:enable Metrics/AbcSize,Metrics/PerceivedComplexity

        sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def release_details
          release_date_info = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

          begin
            repositories.map do |repository_details|
              url = repository_details.fetch("url")
              next unless url == Gradle::FileParser::RepositoriesFinder::CENTRAL_REPO_URL

              release_info_metadata(repository_details).css("a[title]").each do |link|
                version_string = link["title"]
                version = version_string.gsub(%r{/$}, "")
                raw_date_text = link.next.text.strip.split("\n").last.strip

                release_date = begin
                  Time.parse(raw_date_text)
                rescue StandardError
                  nil
                end

                next unless version && version_class.correct?(version)

                release_date_info[version] = {
                  release_date: release_date
                }
              end
            end

            release_date_info
          rescue StandardError
            Dependabot.logger.error("Failed to get release date")
            {}
          end
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def repositories
          return @repositories if @repositories

          details = if plugin?
                      plugin_repository_details + credentials_repository_details
                    else
                      dependency_repository_details + credentials_repository_details
                    end

          @repositories =
            details.reject do |repo|
              next if repo["auth_headers"]

              # Reject this entry if an identical one with non-empty auth_headers exists
              details.any? { |r| r["url"] == repo["url"] && r["auth_headers"] != {} }
            end
        end

        sig { returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
        def google_version_details
          url = Gradle::FileParser::RepositoriesFinder::GOOGLE_MAVEN_REPO
          group_id, artifact_id = group_and_artifact_ids

          dependency_metadata_url = "#{Gradle::FileParser::RepositoriesFinder::GOOGLE_MAVEN_REPO}/" \
                                    "#{T.must(group_id).tr('.', '/')}/" \
                                    "group-index.xml"

          @google_version_details ||=
            begin
              response = Dependabot::RegistryClient.get(url: dependency_metadata_url)
              Nokogiri::XML(response.body)
            end

          xpath = "/#{group_id}/#{artifact_id}"
          return unless @google_version_details.at_xpath(xpath)

          @google_version_details.at_xpath(xpath)
                                 .attributes.fetch("versions")
                                 .value.split(",")
                                 .select { |v| version_class.correct?(v) }
                                 .map { |v| version_class.new(v) }
                                 .map { |version| { version: version, source_url: url } }
        rescue Nokogiri::XML::XPath::SyntaxError
          nil
        end

        sig { params(repository_details: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
        def dependency_metadata(repository_details)
          @dependency_metadata ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
          @dependency_metadata[repository_details.hash] ||=
            begin
              response = Dependabot::RegistryClient.get(
                url: dependency_metadata_url(repository_details.fetch("url")),
                headers: repository_details.fetch("auth_headers")
              )

              check_response(response, repository_details.fetch("url"))
              Nokogiri::XML(response.body)
            rescue URI::InvalidURIError
              Nokogiri::XML("")
            rescue Excon::Error::Socket, Excon::Error::Timeout,
                   Excon::Error::TooManyRedirects
              raise if central_repo_urls.include?(repository_details["url"])

              Nokogiri::XML("")
            end
        end

        sig { params(repository_details: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
        def release_info_metadata(repository_details)
          @release_info_metadata ||= T.let({}, T.nilable(T::Hash[Integer, T.untyped]))
          @release_info_metadata[repository_details.hash] ||=
            begin
              response = Dependabot::RegistryClient.get(
                url: dependency_metadata_url(repository_details.fetch("url")).gsub("maven-metadata.xml", ""),
                headers: repository_details.fetch("auth_headers")
              )

              check_response(response, repository_details.fetch("url"))
              Nokogiri::XML(response.body)
            rescue URI::InvalidURIError
              Nokogiri::XML("")
            rescue Excon::Error::Socket, Excon::Error::Timeout,
                   Excon::Error::TooManyRedirects
              raise if central_repo_urls.include?(repository_details["url"])

              Nokogiri::XML("")
            end
        end

        sig { returns(T::Array[T::Hash[String, String]]) }
        def repository_urls
          plugin? ? plugin_repository_details : dependency_repository_details
        end

        sig { params(response: T.untyped, repository_url: T.untyped).returns(T.nilable(T::Array[T.untyped])) }
        def check_response(response, repository_url)
          return unless response.status == 401 || response.status == 403
          return if T.must(@forbidden_urls).include?(repository_url)
          return if central_repo_urls.include?(repository_url)

          T.must(@forbidden_urls) << repository_url
        end

        sig { returns(T::Array[T::Hash[String, String]]) }
        def credentials_repository_details
          credentials
            .select { |cred| cred["type"] == "maven_repository" }
            .map do |cred|
            {
              "url" => cred.fetch("url").gsub(%r{/+$}, ""),
              "auth_headers" => auth_headers(cred.fetch("url").gsub(%r{/+$}, ""))
            }
          end
        end

        sig { returns(T::Array[T::Hash[String, String]]) }
        def dependency_repository_details
          requirement_files =
            dependency.requirements
                      .map { |r| r.fetch(:file) }
                      .map { |nm| dependency_files.find { |f| f.name == nm } }

          @dependency_repository_details ||=
            requirement_files.flat_map do |target_file|
              Gradle::FileParser::RepositoriesFinder.new(
                dependency_files: dependency_files,
                target_dependency_file: target_file
              ).repository_urls
                                                    .map do |url|
                { "url" => url, "auth_headers" => {} }
              end
            end.uniq
        end

        sig { returns(T::Array[T::Hash[String, String]]) }
        def plugin_repository_details
          [{
            "url" => Gradle::FileParser::RepositoriesFinder::GRADLE_PLUGINS_REPO,
            "auth_headers" => {}
          }] + dependency_repository_details
        end

        sig { params(comparison_version: T.untyped).returns(T::Boolean) }
        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type = T.must(dependency.version)
                          .gsub("native-mt", "native_mt")
                          .split(/[.\-]/)
                          .find do |type|
            Dependabot::Gradle::UpdateChecker::VersionFinder::TYPE_SUFFICES.find { |s| type.include?(s) }
          end

          version_type = comparison_version.to_s
                                           .gsub("native-mt", "native_mt")
                                           .split(/[.\-]/)
                                           .find do |type|
            Dependabot::Gradle::UpdateChecker::VersionFinder::TYPE_SUFFICES.find { |s| type.include?(s) }
          end

          current_type == version_type
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          filename = T.must(dependency.requirements.first).fetch(:file)
          dependency_files.find { |f| f.name == filename }
        end

        sig { params(repository_url: T.untyped).returns(String) }
        def dependency_metadata_url(repository_url)
          group_id, artifact_id = group_and_artifact_ids
          group_id = "#{Dependabot::Gradle::MetadataFinder::KOTLIN_PLUGIN_REPO_PREFIX}.#{group_id}" if kotlin_plugin?

          "#{repository_url}/" \
            "#{T.must(group_id).tr('.', '/')}/" \
            "#{artifact_id}/" \
            "maven-metadata.xml"
        end

        sig { returns(T::Array[String]) }
        def group_and_artifact_ids
          if kotlin_plugin?
            [dependency.name,
             "#{Dependabot::Gradle::MetadataFinder::KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}.gradle.plugin"]
          elsif plugin?
            [dependency.name, "#{dependency.name}.gradle.plugin"]
          else
            dependency.name.split(":")
          end
        end

        sig { returns(T::Boolean) }
        def plugin?
          dependency.requirements.any? { |r| r.fetch(:groups).include? "plugins" }
        end

        sig { returns(T.nilable(T::Boolean)) }
        def kotlin_plugin?
          plugin? && dependency.requirements.any? { |r| r.fetch(:groups).include? "kotlin" }
        end

        sig { returns(T::Array[String]) }
        def central_repo_urls
          central_url_without_protocol =
            Gradle::FileParser::RepositoriesFinder::CENTRAL_REPO_URL
            .gsub(%r{^.*://}, "")

          %w(http:// https://).map { |p| p + central_url_without_protocol }
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(Dependabot::Maven::Utils::AuthHeadersFinder) }
        def auth_headers_finder
          @auth_headers_finder ||= T.let(
            Dependabot::Maven::Utils::AuthHeadersFinder.new(credentials),
            T.nilable(Dependabot::Maven::Utils::AuthHeadersFinder)
          )
        end

        sig { params(maven_repo_url: String).returns(T::Hash[String, String]) }
        def auth_headers(maven_repo_url)
          auth_headers_finder.auth_headers(maven_repo_url)
        end
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/gradle/file_parser/repositories_finder"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/version"
require "dependabot/gradle/requirement"
require "dependabot/gradle/distributions"
require "dependabot/maven/utils/auth_headers_finder"
require "sorbet-runtime"
require "dependabot/logger"
require "dependabot/gradle/metadata_finder"
require "dependabot/gradle/package/release_date_extractor"

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

              next distribution_version_details if url == Gradle::Distributions::DISTRIBUTION_REPOSITORY_URL
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
              released_at: info[:released_at] || release_date_info[version]&.fetch(:release_date),
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

        sig { params(release: Dependabot::Package::PackageRelease).returns(Dependabot::Package::PackageRelease) }
        def fetch_release_metadata(release:)
          return release if release.released_at

          release_date = release_details[release.version.to_s]&.fetch(:release_date, nil)
          hydrated_release = build_release_with_date(release, release_date)

          return hydrated_release if hydrated_release.released_at || !plugin?

          fallback_release_date = version_release_date_fallback(release.version.to_s)
          build_release_with_date(hydrated_release, fallback_release_date)
        end

        sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
        def release_details
          extractor = ReleaseDateExtractor.new(
            dependency_name: dependency.name,
            version_class: version_class
          )
          extractor.extract(
            repositories: repositories,
            dependency_metadata_fetcher: ->(repo) { dependency_metadata(repo) },
            release_info_metadata_fetcher: ->(repo) { release_info_metadata(repo) },
            version_release_date_fetcher: nil
          )
        end

        # Fallback: fetch Last-Modified header from the POM file for a version
        sig { params(version: String).returns(T.nilable(Time)) }
        def version_release_date_fallback(version)
          repositories.each do |repo|
            repository_url = repo.fetch("url")
            pom_url = plugin_version_pom_url(repository_url, version)

            begin
              response = Dependabot::RegistryClient.head(url: pom_url, headers: repo["auth_headers"])
              last_modified = response.headers["Last-Modified"] || response.headers["last-modified"]

              next unless last_modified

              released_at = Time.httpdate(last_modified)
              Dependabot.logger.info(
                "Using POM Last-Modified fallback for #{dependency.name} version #{version} from " \
                "#{repository_url}: #{released_at}"
              )
              return released_at
            rescue StandardError => e
              Dependabot.logger.debug(
                "Failed POM Last-Modified fallback for #{dependency.name} version #{version} from " \
                "#{repository_url}: #{e.message}"
              )
            end
          end

          Dependabot.logger.debug(
            "No POM Last-Modified fallback release date found for #{dependency.name} version #{version}"
          )
          nil
        end

        sig { params(repository_url: String, version: String).returns(String) }
        def plugin_version_pom_url(repository_url, version)
          group_id, artifact_id = group_and_artifact_ids
          group_id = "#{Dependabot::Gradle::MetadataFinder::KOTLIN_PLUGIN_REPO_PREFIX}.#{group_id}" if kotlin_plugin?

          pom_filename = "#{artifact_id}-#{version}.pom"
          File.join(repository_url, T.must(group_id).tr(".", "/"), artifact_id, version, pom_filename)
        end

        sig do
          params(
            release: Dependabot::Package::PackageRelease,
            release_date: T.nilable(Time)
          ).returns(Dependabot::Package::PackageRelease)
        end
        def build_release_with_date(release, release_date)
          Dependabot::Package::PackageRelease.new(
            version: release.version,
            released_at: release_date,
            latest: release.latest,
            yanked: release.yanked,
            yanked_reason: release.yanked_reason,
            downloads: release.downloads,
            url: release.url,
            package_type: release.package_type,
            language: release.language,
            tag: release.tag,
            details: release.details
          )
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def repositories
          return @repositories if @repositories

          details = if distribution?
                      distribution_repository_details
                    elsif plugin?
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
        def distribution_version_details
          DistributionsFetcher.available_versions.map do |info|
            release_date = begin
              Time.parse(info[:build_time])
            rescue StandardError
              nil
            end

            {
              version: info[:version],
              released_at: release_date,
              source_url: Distributions::DISTRIBUTION_REPOSITORY_URL
            }
          end
        rescue StandardError
          nil
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

        # Fetches HTML directory listing from Maven-compatible repositories.
        # Uses CSS selector "a[title]" to extract versions and dates. Caches results per repository.
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
              Nokogiri::HTML(response.body)
            rescue URI::InvalidURIError
              Nokogiri::HTML("")
            rescue Excon::Error::Socket, Excon::Error::Timeout,
                   Excon::Error::TooManyRedirects
              raise if central_repo_urls.include?(repository_details["url"])

              Nokogiri::HTML("")
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
                target_dependency_file: target_file,
                credentials: credentials
              ).repository_urls
                                                    .map do |url|
                { "url" => url, "auth_headers" => auth_headers(url) }
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

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def distribution_repository_details
          [{
            "url" => Gradle::Distributions::DISTRIBUTION_REPOSITORY_URL,
            "auth_headers" => {}
          }]
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

        sig { returns(T::Boolean) }
        def distribution?
          Distributions.distribution_requirements?(dependency.requirements)
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

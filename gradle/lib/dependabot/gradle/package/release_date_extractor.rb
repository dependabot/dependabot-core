# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "time"
require "sorbet-runtime"
require "dependabot/logger"

module Dependabot
  module Gradle
    module Package
      # Extracts release dates from repository metadata to support the cooldown feature.
      # Handles multiple repository formats (Maven Central HTML listings, Gradle Plugin Portal XML).
      class ReleaseDateExtractor
        extend T::Sig

        sig do
          params(
            dependency_name: String,
            version_class: T.class_of(Dependabot::Version)
          ).void
        end
        def initialize(dependency_name:, version_class:)
          @dependency_name = dependency_name
          @version_class = version_class
        end

        # Extracts release dates from all repositories.
        # Attempts both parsing strategies for all repositories:
        # 1. Gradle Plugin Portal style: maven-metadata.xml with lastUpdated timestamp (latest version only)
        # 2. Maven repository style: HTML directory listings with per-version dates
        # This supports mirrors/proxies of both Maven Central and Gradle Plugin Portal.
        sig do
          params(
            repositories: T::Array[T::Hash[String, T.untyped]],
            dependency_metadata_fetcher: T.proc.params(
              repo: T::Hash[String, T.untyped]
            ).returns(Nokogiri::XML::Document),
            release_info_metadata_fetcher: T.proc.params(
              repo: T::Hash[String, T.untyped]
            ).returns(Nokogiri::HTML::Document)
          ).returns(T::Hash[String, T::Hash[Symbol, T.untyped]])
        end
        def extract(repositories:, dependency_metadata_fetcher:, release_info_metadata_fetcher:)
          release_date_info = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

          begin
            repositories.each do |repository_details|
              parse_gradle_plugin_portal_release(
                repository_details,
                release_date_info,
                dependency_metadata_fetcher
              )

              parse_maven_central_releases(
                repository_details,
                release_date_info,
                release_info_metadata_fetcher
              )
            end

            release_date_info
          rescue StandardError => e
            Dependabot.logger.error(
              "Failed to get release date for #{@dependency_name}: #{e.class} - #{e.message}"
            )
            Dependabot.logger.error(e.backtrace&.join("\n") || "No backtrace available")
            {}
          end
        end

        private

        sig { returns(String) }
        attr_reader :dependency_name

        sig { returns(T.class_of(Dependabot::Version)) }
        attr_reader :version_class

        # Parses Maven-style HTML directory listings to extract release dates.
        sig do
          params(
            repository_details: T::Hash[String, T.untyped],
            release_date_info: T::Hash[String, T::Hash[Symbol, T.untyped]],
            metadata_fetcher: T.proc.params(
              repo: T::Hash[String, T.untyped]
            ).returns(Nokogiri::HTML::Document)
          ).void
        end
        def parse_maven_central_releases(repository_details, release_date_info, metadata_fetcher)
          metadata_fetcher.call(repository_details).css("a[title]").each do |link|
            title = link["title"]
            next unless title

            version = title.gsub(%r{/$}, "")
            next unless version_class.correct?(version)
            next if release_date_info.key?(version)

            release_date = extract_release_date_from_link(link, version)
            release_date_info[version] = { release_date: release_date }
          end
        rescue StandardError => e
          Dependabot.logger.debug(
            "Could not parse Maven-style release dates from #{repository_details.fetch('url')} " \
            "for #{dependency_name}: #{e.message}"
          )
        end

        # Parses Gradle Plugin Portal maven-metadata.xml for release dates.
        sig do
          params(
            repository_details: T::Hash[String, T.untyped],
            release_date_info: T::Hash[String, T::Hash[Symbol, T.untyped]],
            metadata_fetcher: T.proc.params(
              repo: T::Hash[String, T.untyped]
            ).returns(Nokogiri::XML::Document)
          ).void
        end
        def parse_gradle_plugin_portal_release(repository_details, release_date_info, metadata_fetcher)
          metadata_xml = metadata_fetcher.call(repository_details)
          last_updated = metadata_xml.at_xpath("//metadata/versioning/lastUpdated")&.text&.strip
          latest_version = metadata_xml.at_xpath("//metadata/versioning/latest")&.text&.strip

          return unless latest_version && version_class.correct?(latest_version)
          return if release_date_info.key?(latest_version)

          release_date = parse_gradle_timestamp(last_updated)
          Dependabot.logger.info(
            "Parsed Gradle Plugin Portal release for #{dependency_name}: #{latest_version} at #{release_date}"
          )
          release_date_info[latest_version] = { release_date: release_date }
        rescue StandardError => e
          Dependabot.logger.debug(
            "Could not parse Gradle Plugin Portal metadata from #{repository_details.fetch('url')} " \
            "for #{dependency_name}: #{e.message}"
          )
        end

        # Extracts release date from HTML link element's adjacent text.
        sig { params(link: Nokogiri::XML::Element, version: String).returns(T.nilable(Time)) }
        def extract_release_date_from_link(link, version)
          raw_date_text = link.next.text.strip.split("\n").last.strip
          Time.parse(raw_date_text)
        rescue StandardError => e
          Dependabot.logger.debug(
            "Failed to parse release date for #{dependency_name} version #{version}: #{e.message}"
          )
          nil
        end

        # Parses Gradle Plugin Portal timestamp format (YYYYMMDDHHmmss).
        sig { params(timestamp: T.nilable(String)).returns(T.nilable(Time)) }
        def parse_gradle_timestamp(timestamp)
          return nil if timestamp.nil? || timestamp.empty?

          Time.strptime(timestamp, "%Y%m%d%H%M%S")
        rescue ArgumentError => e
          Dependabot.logger.warn(
            "Failed to parse Gradle timestamp for #{dependency_name}: '#{timestamp}' - #{e.message}"
          )
          nil
        end
      end
    end
  end
end

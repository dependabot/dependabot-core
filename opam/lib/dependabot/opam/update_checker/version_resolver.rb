# typed: strict
# frozen_string_literal: true

require "dependabot/opam/update_checker"
require "dependabot/opam/version"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/security_advisory"
require "dependabot/shared_helpers"
require "excon"
require "json"

module Dependabot
  module Opam
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      # Resolves latest available version from opam repository
      class VersionResolver
        extend T::Sig

        OPAM_REPO_URL = "https://opam.ocaml.org"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            raise_on_ignored: T::Boolean,
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          raise_on_ignored:,
          security_advisories:
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @raise_on_ignored = raise_on_ignored
          @security_advisories = security_advisories
        end

        sig { returns(T.nilable(Dependabot::Opam::Version)) }
        def latest_version
          @latest_version ||= T.let(
            begin
              versions = fetch_versions_from_registry
              return nil if versions.empty?

              # Filter out ignored versions
              candidate_versions = versions.reject do |version|
                ignore_version?(version)
              end

              return nil if candidate_versions.empty?

              # Return the latest version
              candidate_versions.max
            end,
            T.nilable(Dependabot::Opam::Version)
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T::Array[Dependabot::Opam::Version]) }
        def fetch_versions_from_registry
          # Fetch available versions from opam repository API
          # The opam repository has a JSON API at:
          # https://opam.ocaml.org/packages/[package-name]/

          package_name = dependency.name
          url = "#{OPAM_REPO_URL}/packages/#{package_name}/"

          begin
            response = Excon.get(
              url,
              headers: { "Accept" => "application/json" },
              idempotent: true,
              **Dependabot::SharedHelpers.excon_defaults
            )

            return [] unless response.status == 200

            parse_versions_from_response(response.body)
          rescue Excon::Error::Timeout, Excon::Error::Socket
            # Network error - return empty array
            []
          rescue JSON::ParserError
            # Invalid JSON - return empty array
            []
          end
        end

        sig { params(body: String).returns(T::Array[Dependabot::Opam::Version]) }
        def parse_versions_from_response(body)
          versions = []

          # Extract versions from href links: href="../package-name/package-name.version/"
          # This pattern matches version directory links, including versions with 'v' prefix
          package_name = dependency.name
          escaped_name = Regexp.escape(package_name)
          pattern = %r{(?:href|src)="[^"]*#{escaped_name}/#{escaped_name}\.([v]?[0-9][^"/]*)/?"}i

          body.scan(pattern) do |match|
            version_string = match[0]
            next unless valid_version?(version_string)

            versions << Dependabot::Opam::Version.new(version_string)
          end

          # Also extract current/latest version from title-group (not in dropdown or dependencies)
          # Pattern: <h2>PACKAGENAME<span class="title-group">version...<span class="package-version">X.Y.Z</span>
          # More specific to avoid matching versions from Dependencies section
          title_pattern = %r{
            <h2>#{escaped_name}<span[^>]*class="title-group"[^>]*>.*?
            <span\sclass="package-version">([v]?[0-9][^<]+)</span>
          }mix
          title_match = body.match(title_pattern)
          if title_match
            version_string = T.must(title_match[1])
            versions << Dependabot::Opam::Version.new(version_string) if valid_version?(version_string)
          end

          versions.uniq.sort
        rescue StandardError
          []
        end

        sig { params(version_string: String).returns(T::Boolean) }
        def valid_version?(version_string)
          # Skip date-like versions (8 digits like 20230213, or YYYY.MM.DD format like 2025.02.17)
          return false if version_string.match?(/^\d{8}$/) # e.g. 20230213
          return false if version_string.match?(/^[12]\d{3}\.\d{1,2}\.\d{1,2}$/) # e.g. 2025.02.17
          return false unless version_string.include?(".")
          return false unless Dependabot::Opam::Version.correct?(version_string)

          true
        end

        sig { params(version: Dependabot::Opam::Version).returns(T::Boolean) }
        def ignore_version?(version)
          ignored_versions.any? do |ignored|
            version.to_s == ignored || version.to_s.start_with?("#{ignored}.")
          end
        end
      end
    end
  end
end

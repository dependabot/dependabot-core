# typed: strong
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

          # Try to parse HTML response and extract versions
          # The opam website lists versions in package directories
          # Format: package-name.version
          package_name = dependency.name

          body.scan(/#{Regexp.escape(package_name)}\.([0-9][^"<\s]*)/) do |match|
            version_string = match[0]
            next unless Dependabot::Opam::Version.correct?(version_string)

            versions << Dependabot::Opam::Version.new(version_string)
          end

          versions.uniq.sort
        rescue StandardError
          []
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

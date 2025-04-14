# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/cargo"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Cargo
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        CRATES_IO_API = "https://crates.io/api/v1/crates"
        PACKAGE_TYPE = "gem"
        PACKAGE_LANGUAGE = "rust"

        # fallback for empty requirement
        RUST_REQUIREMENT = "1.0"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials

          @source_type = T.let(nil, T.nilable(String))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig do
          returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def fetch
          package_releases = crates_listing.fetch("versions", []).reject { |v| v["yanked"] }.map do |release|
            package_release(
              version: release["num"] || release["vers"],
              released_at: release["created_at"] ? Time.parse(release["created_at"]) : nil,
              downloads: release["downloads"],
              url: "#{CRATES_IO_API}/#{release['dl_path']}",
              rust_version: release["rust"]
            )
          end

          package_details(package_releases)
        end

        private

        sig do
          returns(T.untyped)
        end
        def crates_listing
          return @crates_listing unless @crates_listing.nil?

          info = fetch_dependency_info
          index = fetch_index(info)

          hdrs = default_headers
          hdrs.merge!(auth_headers(info)) if index != CRATES_IO_API

          url = metadata_fetch_url(dependency, index)

          Dependabot.logger.info("Calling #{url} to fetch metadata for #{dependency.name} from #{index}")

          response = fetch_response(url, hdrs)
          return {} if response.status == 404

          @crates_listing = T.let(parse_response(response, index), T.nilable(T::Hash[T.untyped, T.untyped]))

          Dependabot.logger.info("Fetched metadata for #{dependency.name} from #{index} successfully")

          @crates_listing
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def fetch_dependency_info
          dependency.requirements.filter_map { |r| r[:source] }.first
        end

        sig { params(info: T.untyped).returns(String) }
        def fetch_index(info)
          (info && info[:index]) || CRATES_IO_API
        end

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def default_headers
          { "User-Agent" => "Dependabot (dependabot.com)" }
        end

        sig { params(info: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
        def auth_headers(info)
          registry_creds = credentials.find do |cred|
            cred["type"] == "cargo_registry" && cred["registry"] == info[:name]
          end

          return {} if registry_creds.nil?

          token = registry_creds["token"] || "placeholder_token"
          { "Authorization" => token }
        end

        sig { params(url: String, headers: T.untyped).returns(Excon::Response) }
        def fetch_response(url, headers)
          Excon.get(
            url,
            idempotent: true,
            **SharedHelpers.excon_defaults(headers: headers)
          )
        end

        sig { params(response: Excon::Response, index: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
        def parse_response(response, index)
          if index.start_with?("sparse+")
            parsed_response = response.body.lines.map { |line| JSON.parse(line) }
            { "versions" => parsed_response }
          else
            JSON.parse(response.body)
          end
        end

        sig { params(dependency: T.untyped, index: T.untyped).returns(String) }
        def metadata_fetch_url(dependency, index)
          return "#{index}/#{dependency.name}" if index == CRATES_IO_API

          # Determine cargo's index file path for the dependency
          index = index.delete_prefix("sparse+")
          name_length = dependency.name.length
          dependency_path = case name_length
                            when 1, 2
                              "#{name_length}/#{dependency.name}"
                            when 3
                              "#{name_length}/#{dependency.name[0..1]}/#{dependency.name}"
                            else
                              "#{dependency.name[0..1]}/#{dependency.name[2..3]}/#{dependency.name}"
                            end

          "#{index}#{'/' unless index.end_with?('/')}#{dependency_path}"
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return true if dependency.numeric_version&.prerelease?

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end

        sig do
          params(
            version: String,
            released_at: T.nilable(Time),
            downloads: T.nilable(Integer),
            url: T.nilable(String),
            rust_version: T.nilable(String),
            yanked: T::Boolean
          ).returns(Dependabot::Package::PackageRelease)
        end
        def package_release(version:, released_at:, downloads:, url:, rust_version:, yanked: false)
          Dependabot::Package::PackageRelease.new(
            version: Cargo::Version.new(version),
            released_at: released_at,
            yanked: yanked,
            yanked_reason: nil,
            downloads: downloads,
            url: url,
            package_type: PACKAGE_TYPE,
            language: Dependabot::Package::PackageLanguage.new(
              name: PACKAGE_LANGUAGE,
              version: nil,
              requirement: language_requirement(rust_version)
            )
          )
        end

        sig { params(req_string: T.nilable(String)).returns(T.nilable(Requirement)) }
        def language_requirement(req_string)
          return Requirement.new(req_string) if req_string && !req_string.empty?

          nil
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(Dependabot::Package::PackageDetails)
        end
        def package_details(releases)
          @package_details ||= T.let(
            Dependabot::Package::PackageDetails.new(
              dependency: dependency,
              releases: releases.reverse.uniq(&:version)
            ), T.nilable(Dependabot::Package::PackageDetails)
          )
        end
      end
    end
  end
end

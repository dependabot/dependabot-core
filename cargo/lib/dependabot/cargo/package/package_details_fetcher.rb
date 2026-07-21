# typed: strict
# frozen_string_literal: true

require "json"
require "time"
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

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def fetch
          releases = T.cast(crates_listing.fetch("versions", []), T::Array[T::Hash[String, T.anything]])
          package_releases = releases.reject { |v| v["yanked"] }.map do |release|
            created_at = T.cast(release["created_at"], T.nilable(String))
            package_release(
              version: T.cast(release["num"], T.nilable(String)) || T.cast(release["vers"], String),
              released_at: created_at ? Time.parse(created_at) : nil,
              downloads: T.cast(release["downloads"], T.nilable(Integer)),
              url: "#{CRATES_IO_API}/#{T.cast(release['dl_path'], T.nilable(String))}",
              rust_version: T.cast(release["rust"], T.nilable(String))
            )
          end

          package_details(package_releases)
        end

        private

        sig do
          returns(T::Hash[String, T.anything])
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

          @crates_listing = T.let(parse_response(response, index), T.nilable(T::Hash[String, T.anything]))

          Dependabot.logger.info("Fetched metadata for #{dependency.name} from #{index} successfully")

          T.must(@crates_listing)
        end

        sig { returns(T.nilable(Dependabot::DependencyRequirement::Details)) }
        def fetch_dependency_info
          dependency.requirements.filter_map(&:source).first
        end

        sig { params(info: T.nilable(Dependabot::DependencyRequirement::Details)).returns(String) }
        def fetch_index(info)
          raw_index = info && (info[:index] || info["index"])
          raw_index.is_a?(String) ? raw_index : CRATES_IO_API
        end

        sig { returns(T::Hash[String, String]) }
        def default_headers
          { "User-Agent" => "Dependabot (dependabot.com)" }
        end

        sig do
          params(info: T.nilable(Dependabot::DependencyRequirement::Details))
            .returns(T::Hash[String, String])
        end
        def auth_headers(info)
          raw_registry_name = info && (info[:name] || info["name"])
          registry_name = raw_registry_name if raw_registry_name.is_a?(String)
          registry_creds = credentials.find do |cred|
            cred["type"] == "cargo_registry" && cred["registry"] == registry_name
          end

          return {} unless registry_creds

          token = registry_creds["token"] || "placeholder_token"
          { "Authorization" => token }
        end

        sig { params(url: String, headers: T::Hash[String, String]).returns(Excon::Response) }
        def fetch_response(url, headers)
          Excon.get(
            url,
            idempotent: true,
            **SharedHelpers.excon_defaults(headers: headers)
          )
        end

        sig { params(response: Excon::Response, index: String).returns(T::Hash[String, T.anything]) }
        def parse_response(response, index)
          if index.start_with?("sparse+")
            parsed_response = response.body.lines
                                      .map(&:strip)
                                      .reject(&:empty?)
                                      .filter_map do |line|
              JSON.parse(line)
            rescue JSON::ParserError => e
              Dependabot.logger.warn("Failed to parse line in sparse index: #{e.message}")
              nil
            end

            { "versions" => parsed_response }
          else
            JSON.parse(response.body)
          end
        end

        sig { params(dependency: Dependabot::Dependency, index: String).returns(String) }
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
            reqs = (req.requirement || "").split(",").map(&:strip)
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
            ),
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end
      end
    end
  end
end

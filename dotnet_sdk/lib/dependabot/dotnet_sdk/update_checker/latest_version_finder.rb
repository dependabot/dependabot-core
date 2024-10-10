# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/dotnet_sdk/requirement"
require "dependabot/dotnet_sdk/version"
require "dependabot/registry_client"
require "dependabot/update_checkers/base"

module Dependabot
  module DotnetSdk
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder
        extend T::Sig

        RELEASES_INDEX_URL = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"

        sig { params(dependency: Dependabot::Dependency, ignored_versions: T::Array[String]).void }
        def initialize(dependency:, ignored_versions:)
          @dependency = dependency
          @ignored_versions = ignored_versions
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          @latest_version ||= T.let(
            fetch_latest_version,
            T.nilable(Dependabot::Version)
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_latest_version
          versions = available_versions
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions.max
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def available_versions
          releases.map { |v| version_class.new(v) }
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_prerelease_versions(versions)
          return versions if wants_prerelease?

          # This isn't entirely accurate. .NET considers release candidates to NOT be pre-releases.
          # However, we want to be conservative.
          # See https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core
          versions.reject(&:prerelease?)
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_ignored_versions(versions)
          versions.reject do |version|
            ignore_requirements.any? { |r| r.satisfied_by?(version) }
          end
        end

        sig { returns(T::Array[String]) }
        def releases
          response = releases_response
          return [] unless response.status == 200

          parsed = JSON.parse(response.body)
          parsed["releases-index"].flat_map do |release|
            release_channel(release["releases.json"])
          end
        end

        sig { returns(Excon::Response) }
        def releases_response
          Dependabot::RegistryClient.get(
            url: RELEASES_INDEX_URL,
            headers: { "Accept" => "application/json" }
          )
        end

        sig { params(url: String).returns(T::Array[String]) }
        def release_channel(url)
          response = release_channel_response(url)
          begin
            parsed = JSON.parse(T.must(response).body)
          rescue JSON::ParserError
            raise Dependabot::DependencyFileNotResolvable, "Invalid JSON response from #{url}"
          end

          parsed["releases"].map do |release|
            if release["sdks"].nil?
              release["sdk"]["version"]
            else
              release["sdks"].flat_map { |sdk| sdk["version"] }
            end
          end
        .flatten
        end

        sig { params(url: String).returns(T.nilable(Excon::Response)) }
        def release_channel_response(url)
          Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => "application/json" }
          )
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          dependency.metadata[:allow_prerelease]
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end
      end
    end
  end
end

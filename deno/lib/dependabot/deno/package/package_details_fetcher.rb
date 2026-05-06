# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/deno/version"

module Dependabot
  module Deno
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions
          source_type = dependency.requirements.first&.dig(:source, :type)

          case source_type
          when "jsr"
            fetch_jsr_releases
          when "npm"
            fetch_npm_releases
          else
            []
          end
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_jsr_releases
          name = dependency.name
          url = "https://jsr.io/#{name}/meta.json"

          response = Dependabot::RegistryClient.get(url: url)
          data = JSON.parse(response.body)

          data.fetch("versions", {}).filter_map do |version_str, meta|
            next unless Deno::Version.correct?(version_str)

            yanked = meta.is_a?(Hash) && meta["yanked"] == true
            released_at = parse_time(meta["createdAt"]) if meta.is_a?(Hash)

            Dependabot::Package::PackageRelease.new(
              version: Deno::Version.new(version_str),
              released_at: released_at,
              yanked: yanked
            )
          end
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket
          []
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_npm_releases
          name = dependency.name
          url = "https://registry.npmjs.org/#{name}"

          response = Dependabot::RegistryClient.get(url: url)
          data = JSON.parse(response.body)

          time_data = data.fetch("time", {})

          data.fetch("versions", {}).filter_map do |version_str, _meta|
            next unless Deno::Version.correct?(version_str)

            released_at = parse_time(time_data[version_str])

            Dependabot::Package::PackageRelease.new(
              version: Deno::Version.new(version_str),
              released_at: released_at
            )
          end
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket
          []
        end

        sig { params(time_str: T.nilable(String)).returns(T.nilable(Time)) }
        def parse_time(time_str)
          return nil unless time_str

          Time.parse(time_str)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end

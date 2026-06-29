# typed: strict
# frozen_string_literal: true

require "cgi"
require "json"
require "time"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/package/package_release"
require "dependabot/devbox/version"

module Dependabot
  module Devbox
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        SEARCH_URL = T.let("https://search.devbox.sh/v1/search", String)

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions
          package = fetch_package
          return [] unless package

          versions = package["versions"]
          return [] unless versions.is_a?(Array)

          versions.filter_map do |version_data|
            next unless version_data.is_a?(Hash)

            version_str = version_data["version"]
            next unless version_str.is_a?(String) && Devbox::Version.correct?(version_str)

            Dependabot::Package::PackageRelease.new(
              version: Devbox::Version.new(version_str),
              released_at: release_time(version_data)
            )
          end
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket
          []
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        # Nixhub search is fuzzy and can return several packages; keep only the
        # one whose name matches the dependency exactly.
        sig { returns(T.nilable(Hash)) }
        def fetch_package
          response = Dependabot::RegistryClient.get(
            url: "#{SEARCH_URL}?q=#{CGI.escape(dependency.name)}"
          )
          return nil unless response.status == 200

          data = JSON.parse(response.body)
          packages = data.is_a?(Hash) ? data["packages"] : nil
          return nil unless packages.is_a?(Array)

          packages.find { |pkg| pkg.is_a?(Hash) && pkg["name"] == dependency.name }
        end

        # Approximates a version's release date with the earliest per-system
        # `last_updated` (Unix epoch seconds), falling back to the top-level
        # `last_updated`. `filter_by_cooldown` treats a nil result gracefully.
        sig { params(version_data: Hash).returns(T.nilable(Time)) }
        def release_time(version_data)
          timestamps = []

          systems = version_data["systems"]
          timestamps.concat(systems.values.filter_map { |s| s["last_updated"] if s.is_a?(Hash) }) if systems.is_a?(Hash)
          timestamps << version_data["last_updated"]

          epoch = timestamps.grep(Integer).min
          epoch ? Time.at(epoch).utc : nil
        end
      end
    end
  end
end

# typed: strong
# frozen_string_literal: true

require "dependabot/gradle/version"
require "dependabot/gradle/distributions"
require "sorbet-runtime"

module Dependabot
  module Gradle
    module Package
      class DistributionsFetcher
        extend T::Sig

        @available_versions_cache = T.let({}, T::Hash[String, T::Array[T::Hash[String, T.untyped]]])
        @distributions_checksums = T.let({}, T::Hash[String, T::Array[String]])

        sig do
          params(
            base_url: String,
            auth_headers: T::Hash[String, String]
          ).returns(T.any(T::Array[T::Hash[String, T.untyped]], T::Array[T::Hash[Symbol, T.untyped]]))
        end
        def self.available_versions(
          base_url: Distributions::DISTRIBUTION_REPOSITORY_URL,
          auth_headers: {}
        )
          return T.must(@available_versions_cache[base_url]) if @available_versions_cache[base_url]&.any?

          response = Dependabot::RegistryClient.get(
            url: "#{base_url}/versions/all",
            headers: auth_headers
          )
          versions = T.let(
            JSON.parse(
              T.let(response.body, String),
              symbolize_names: true
            ),
            T::Array[T::Hash[Symbol, T.untyped]]
          )
          @available_versions_cache[base_url] =
            versions
            .select { |v| release_version?(version: v) }
            .uniq { |v| v[:version] }
            .map do |v|
              {
                version: v[:version],
                build_time: v[:buildTime]
              }
            end
        end

        sig { params(version: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def self.release_version?(version:)
          Gradle::Version.correct?(T.let(version[:version], String)) &&
            T.let(version[:broken], T::Boolean) == false &&
            T.let(version[:snapshot], T::Boolean) == false &&
            T.let(version[:rcFor], String) == "" &&
            T.let(version[:milestoneFor], String) == "" &&
            /.*-(rc|milestone)-.*/.match?(T.let(version[:version], String)) == false
        end

        sig do
          params(
            distribution_url: String,
            auth_headers: T::Hash[String, String]
          ).returns(T.nilable(T::Array[String]))
        end
        def self.resolve_checksum(distribution_url, auth_headers: {})
          cached = @distributions_checksums[distribution_url]
          return cached if cached

          checksum_url = "#{distribution_url}.sha256"
          checksum = T.let(
            Dependabot::RegistryClient.get(url: checksum_url, headers: auth_headers).body,
            String
          ).strip
          return nil unless checksum.match?(/\A[a-f0-9]{64}\z/)

          @distributions_checksums[distribution_url] = [checksum_url, checksum]
        end

        private_class_method :release_version?
      end
    end
  end
end

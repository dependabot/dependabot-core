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

        @available_versions = T.let([], T::Array[T::Hash[Symbol, Object]])
        @distributions_checksums = T.let({}, T::Hash[String, T::Array[String]])

        sig { returns(T::Array[T::Hash[Symbol, Object]]) }
        def self.available_versions
          return @available_versions if @available_versions.any?

          response = Dependabot::RegistryClient.get(url: "https://services.gradle.org/versions/all")
          versions = T.let(
            JSON.parse(
              T.let(response.body, String),
              symbolize_names: true
            ),
            T::Array[T::Hash[Symbol, Object]]
          )
          @available_versions +=
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

        sig { params(version: T::Hash[Symbol, Object]).returns(T::Boolean) }
        def self.release_version?(version:)
          version_number = version[:version]
          return false unless version_number.is_a?(String)

          Gradle::Version.correct?(version_number) &&
            version[:broken] == false &&
            version[:snapshot] == false &&
            version[:rcFor] == "" &&
            version[:milestoneFor] == "" &&
            /.*-(rc|milestone)-.*/.match?(version_number) == false
        end

        sig { params(distribution_url: String).returns(T.nilable(T::Array[String])) }
        def self.resolve_checksum(distribution_url)
          cached = @distributions_checksums[distribution_url]
          return cached if cached

          checksum_url = "#{distribution_url}.sha256"
          checksum = T.let(Dependabot::RegistryClient.get(url: checksum_url).body, String).strip
          return nil unless checksum.match?(/\A[a-f0-9]{64}\z/)

          @distributions_checksums[distribution_url] = [checksum_url, checksum]
        end

        private_class_method :release_version?
      end
    end
  end
end

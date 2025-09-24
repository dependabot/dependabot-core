# typed: strong
# frozen_string_literal: true

require "dependabot/gradle/version"
require "sorbet-runtime"

module Dependabot
  module Gradle
    class UpdateChecker
      class DistributionsFinder
        extend T::Sig

        @available_versions = T.let([], T::Array[T::Hash[String, T.untyped]])
        @distributions_checksums = T.let({}, T::Hash[String, T::Array[String]])

        sig { returns(T.any(T::Array[T::Hash[String, T.untyped]], T::Array[T::Hash[Symbol, T.untyped]])) }
        def self.available_versions
          return @available_versions if @available_versions.any?

          response = Dependabot::RegistryClient.get(url: "https://services.gradle.org/versions/all")
          versions = T.let(
            JSON.parse(
              T.let(response.body, String),
              object_class: OpenStruct
            ),
            T::Array[OpenStruct]
          )
          @available_versions += versions
                                 .select { |v| release_version?(version: v) }
                                 .map { |v| T.let(v["version"], String) }
                                 .uniq
                                 .select { |v| Gradle::Version.correct?(v) }
                                 .map { |v| Gradle::Version.new(v) }
                                 .sort
                                 .map { |version| { version: version, source_url: "https://services.gradle.org" } }
        end

        sig { params(version: OpenStruct).returns(T::Boolean) }
        def self.release_version?(version:)
          T.let(version[:broken], T::Boolean) == false &&
            T.let(version[:snapshot], T::Boolean) == false &&
            T.let(version[:rcFor], String) == "" &&
            T.let(version[:milestoneFor], String) == "" &&
            /.*-(rc|milestone)-.*/.match?(T.let(version[:version], String)) == false
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

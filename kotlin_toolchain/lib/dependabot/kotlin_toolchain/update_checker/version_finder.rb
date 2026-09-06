# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/update_checker/version_finder"
require "dependabot/kotlin_toolchain/package/package_details_fetcher"
require "dependabot/kotlin_toolchain/version"
require "dependabot/package/package_release"
require "dependabot/update_checkers/base"

module Dependabot
  module KotlinToolchain
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class VersionFinder < Dependabot::Gradle::UpdateChecker::VersionFinder
        extend T::Sig

        sig { override.returns(T::Array[T::Hash[Symbol, Object]]) }
        def versions
          package_details_fetcher.fetch_available_versions
        end

        private

        sig do
          override
            .params(
              version_details: T::Array[T::Hash[Symbol, Object]]
            )
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def package_release(version_details)
          version_details.map do |info|
            released_at = info[:released_at]
            Dependabot::Package::PackageRelease.new(
              version: Version.new(info.fetch(:version).to_s),
              released_at: released_at.is_a?(Time) ? released_at : nil,
              url: info[:source_url]&.to_s
            )
          end
        end

        sig { override.returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= T.let(
            Package::PackageDetailsFetcher.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              forbidden_urls: [],
              cooldown_options: cooldown_options
            ),
            T.nilable(Package::PackageDetailsFetcher)
          )
        end
      end
    end
  end
end

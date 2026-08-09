# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/powershell/package/package_details_fetcher"
require "dependabot/powershell/requirement"
require "dependabot/powershell/update_checker"
require "dependabot/powershell/version"

module Dependabot
  module Powershell
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= Dependabot::Powershell::Package::PackageDetailsFetcher
                               .new(dependency: dependency)
                               .fetch
        end

        sig { params(version: String).returns(T.nilable(String)) }
        def manifest_guid_for(version)
          Dependabot::Powershell::Package::PackageDetailsFetcher
            .new(dependency: dependency)
            .manifest_guid_for(version)
        end

        protected

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig do
          override.params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_lowest_security_fix_versions_filter(releases)
          floor = module_version_floor
          return releases unless floor

          releases.select { |release| release.version >= floor }
        end

        private

        sig { returns(T.nilable(Dependabot::Version)) }
        def module_version_floor
          dependency.requirements.filter_map do |requirement|
            metadata = requirement.metadata
            next unless metadata
            next unless %w(ModuleVersion ModuleVersion+MaximumVersion).include?(metadata.fetch(:version_key, nil))

            minimum_version(requirement.requirement)
          end.max
        end

        sig { params(requirement: T.nilable(Dependabot::DependencyRequirement::Requirement)).returns(T.nilable(Dependabot::Version)) }
        def minimum_version(requirement)
          return unless requirement.is_a?(String)

          minimum = requirement.split(",").map(&:strip).find { |constraint| constraint.start_with?(">=") }
          return unless minimum

          version = minimum.delete_prefix(">=").strip
          Version.new(version) if Version.correct?(version)
        end
      end
    end
  end
end

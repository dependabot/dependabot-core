# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/powershell/module_specification_version"
require "dependabot/powershell/package/package_details_fetcher"
require "dependabot/powershell/requirement"
require "dependabot/powershell/update_checker"
require "dependabot/powershell/version"
require "dependabot/update_checkers/cooldown_calculation"

module Dependabot
  module Powershell
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        MODULE_VERSION_KEYS = T.let(%w(ModuleVersion ModuleVersion+MaximumVersion).freeze, T::Array[String])

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= package_details_fetcher.fetch
        end

        sig { params(version: String).returns(String) }
        def manifest_guid_for(version)
          package_details_fetcher.manifest_guid_for(version)
        end

        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def selected_source
          package_details_fetcher.selected_source
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_declaration_version
          releases = available_versions
          return unless releases

          releases = filter_yanked_versions(releases)
          releases = filter_by_cooldown(releases)
          releases = filter_unsupported_versions(releases, nil)
          releases = filter_prerelease_versions(releases)
          releases = filter_ignored_versions(releases)
          releases = filter_module_specification_versions(releases)
          releases.max { |left, right| compare_module_specification_releases(left, right) }&.version
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
        def filter_by_cooldown(releases)
          return super unless package_details_fetcher.mar_source?
          return releases if Dependabot::UpdateCheckers::CooldownCalculation.skip_cooldown?(
            cooldown_options,
            dependency.name,
            cooldown_enabled: true
          )

          cooldown = T.must(cooldown_options)
          current_version_string = dependency.version
          current_version = current_dependency_version
          filtered = releases.select do |release|
            release.version.to_s == current_version_string ||
              Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(
                cooldown,
                current_version,
                release.version
              ).zero?
          end

          if filtered.length < releases.length
            Dependabot.logger.info(
              "Skipped #{releases.length - filtered.length} Microsoft Artifact Registry versions for " \
              "#{dependency.name} because MAR does not expose release timestamps required by the configured cooldown"
            )
          end

          if filtered.empty? && current_version
            return [
              Dependabot::Package::PackageRelease.new(
                version: current_version,
                released_at: nil
              )
            ]
          end

          filtered
        end

        sig do
          override.params(releases: T::Array[Dependabot::Package::PackageRelease])
                  .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_lowest_security_fix_versions_filter(releases)
          releases = filter_module_specification_versions(releases)

          floor = module_version_floor
          return releases unless floor

          releases.select { |release| release.version >= floor }
        end

        private

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_module_specification_versions(releases)
          releases.select { |release| ModuleSpecificationVersion.parse(release.version.to_s) }
        end

        sig do
          params(
            left: Dependabot::Package::PackageRelease,
            right: Dependabot::Package::PackageRelease
          ).returns(Integer)
        end
        def compare_module_specification_releases(left, right)
          left_version = left.to_s
          right_version = right.to_s
          comparison = T.must(ModuleSpecificationVersion.compare(left_version, right_version))
          return comparison unless comparison.zero?

          T.must(left_version <=> right_version)
        end

        sig { returns(Dependabot::Powershell::Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= T.let(
            Dependabot::Powershell::Package::PackageDetailsFetcher.new(dependency: dependency),
            T.nilable(Dependabot::Powershell::Package::PackageDetailsFetcher)
          )
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_dependency_version
          current_version = dependency.version
          return unless version_class.correct?(current_version)

          version_class.new(T.must(current_version))
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def module_version_floor
          dependency.requirements.filter_map do |requirement|
            metadata = requirement.metadata
            next unless metadata
            next unless MODULE_VERSION_KEYS.include?(metadata.fetch(:version_key, nil))

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

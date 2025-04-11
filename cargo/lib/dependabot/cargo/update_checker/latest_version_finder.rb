# typed: true
# frozen_string_literal: true

require "excon"
require "dependabot/cargo/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/cargo/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"
require "sorbet-runtime"

module Dependabot
  module Cargo
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          override.returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def package_details
          @package_details ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          ).fetch
        end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def lowest_security_fix_version
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version(language_version: nil)
        end

        protected

        sig { override.returns(T::Boolean) }
        def wants_prerelease?
          return true if dependency.numeric_version&.prerelease?

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_cargo)
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :ignored_versions
        attr_reader :security_advisories

        def apply_post_fetch_lowest_security_fix_versions_filter(versions)
          filter_prerelease_versions(versions)
        end
      end
    end
  end
end

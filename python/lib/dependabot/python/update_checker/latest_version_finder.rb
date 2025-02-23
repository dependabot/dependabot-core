# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/python/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/package/package_details_fetcher"

module Dependabot
  module Python
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored: false
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored

          @latest_version = T.let(nil, T.nilable(Dependabot::Version))
          @latest_version_with_no_unlock = T.let(nil, T.nilable(Dependabot::Version))
          @lowest_security_fix_version = T.let(nil, T.nilable(Dependabot::Version))
          @available_versions = T.let(nil, T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
          @index_urls = T.let(nil, T.nilable(T::Array[String]))
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Gem::Version))
        end
        def latest_version(python_version: nil)
          @latest_version ||= fetch_latest_version(python_version: python_version)
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Gem::Version))
        end
        def latest_version_with_no_unlock(python_version: nil)
          @latest_version_with_no_unlock ||= fetch_latest_version_with_no_unlock(python_version: python_version)
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Gem::Version))
        end
        def lowest_security_fix_version(python_version: nil)
          @lowest_security_fix_version ||= fetch_lowest_security_fix_version(python_version: python_version)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[SecurityAdvisory]) }
        attr_reader :security_advisories

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(python_version:)
          version_hashes = available_versions
          return unless version_hashes

          version_hashes = filter_yanked_versions(version_hashes)
          versions = filter_unsupported_versions(version_hashes, python_version)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)

          versions.max
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version_with_no_unlock(python_version:)
          version_hashes = available_versions
          return unless version_hashes

          version_hashes = filter_yanked_versions(version_hashes)
          versions = filter_unsupported_versions(version_hashes, python_version)
          versions = filter_prerelease_versions(versions)
          versions = filter_ignored_versions(versions)
          versions = filter_out_of_range_versions(versions)

          versions.max
        end

        sig do
          params(python_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(python_version:)
          version_hashes = available_versions
          return unless version_hashes

          version_hashes = filter_yanked_versions(version_hashes)
          versions = filter_unsupported_versions(version_hashes, python_version)
          # versions = filter_prerelease_versions(versions)
          versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
            versions,
            security_advisories
          )
          versions = filter_ignored_versions(versions)
          versions = filter_lower_versions(versions)

          versions.min
        end

        sig do
          params(releases: T::Array[Dependabot::Python::Package::PackageRelease])
            .returns(T::Array[Dependabot::Python::Package::PackageRelease])
        end
        def filter_yanked_versions(releases)
          filtered = releases.reject(&:yanked?)
          if releases.count > filtered.count
            Dependabot.logger.info("Filtered out #{releases.count - filtered.count} yanked versions")
          end
          filtered
        end

        sig do
          params(
            releases: T::Array[Dependabot::Python::Package::PackageRelease],
            python_version: T.nilable(T.any(String, Version))
          )
            .returns(T::Array[Dependabot::Version])
        end
        def filter_unsupported_versions(releases, python_version)
          filtered = releases.filter_map do |release|
            python_requirement = release.language&.requirement
            next release.version unless python_version
            next release.version unless python_requirement
            next unless python_requirement.satisfied_by?(python_version)

            release.version
          end
          if releases.count > filtered.count
            delta = releases.count - filtered.count
            Dependabot.logger.info("Filtered out #{delta} unsupported Python #{python_version} versions")
          end
          filtered
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          filtered = versions_array.reject(&:prerelease?)

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} pre-release versions")
          end

          filtered
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_ignored_versions(versions_array)
          filtered = versions_array
                     .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise Dependabot::AllVersionsIgnored
          end

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} ignored versions")
          end
          filtered
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array.select { |version| version > dependency.numeric_version }
        end

        sig do
          params(versions_array: T::Array[Dependabot::Version])
            .returns(T::Array[Dependabot::Version])
        end
        def filter_out_of_range_versions(versions_array)
          reqs = dependency.requirements.filter_map do |r|
            requirement_class.requirements_array(r.fetch(:requirement))
          end

          versions_array
            .select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return version_class.new(dependency.version).prerelease? if dependency.version

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.match?(/[A-Za-z]/) }
          end
        end

        # See https://www.python.org/dev/peps/pep-0503/ for details of the
        # Simple Repository API we use here.
        sig do
          returns(T.nilable(T::Array[Dependabot::Python::Package::PackageRelease]))
        end
        def available_versions
          @available_versions ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          ).fetch.releases
        end

        sig { returns(T::Array[T.untyped]) }
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

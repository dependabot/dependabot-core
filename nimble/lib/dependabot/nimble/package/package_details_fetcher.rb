# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/git_commit_checker"
require "dependabot/package/package_details"

require "dependabot/nimble/package_index"
require "dependabot/nimble/version"

module Dependabot
  module Nimble
    module Package
      # The releases of a package: the version tags of its git repository, with the date each tag's
      # commit was made (which cooldown needs).
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            package_index: Dependabot::Nimble::PackageIndex
          ).void
        end
        def initialize(dependency:, credentials: [], package_index: Dependabot::Nimble::PackageIndex.new)
          @dependency = dependency
          @credentials = credentials
          @package_index = package_index
        end

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          url = @package_index.repository_url(@dependency.name)
          return details([]) unless url

          releases = Dependabot::GitCommitChecker
                     .new(dependency: git_dependency(url), credentials: @credentials)
                     .allowed_version_tags_with_release_dates
          details(releases.uniq(&:version))
        rescue Dependabot::GitDependenciesNotReachable
          details([])
        end

        private

        sig { params(releases: T::Array[Dependabot::Package::PackageRelease]).returns(Dependabot::Package::PackageDetails) }
        def details(releases)
          Dependabot::Package::PackageDetails.new(dependency: @dependency, releases: releases)
        end

        # GitCommitChecker lists the tags of a dependency that has a git source.
        sig { params(url: String).returns(Dependabot::Dependency) }
        def git_dependency(url)
          Dependabot::Dependency.new(
            name: @dependency.name,
            version: @dependency.version,
            requirements: [{
              requirement: nil,
              file: "#{@dependency.name}.nimble",
              groups: [],
              source: { type: "git", url: url, branch: nil, ref: nil }
            }],
            package_manager: "nimble"
          )
        end
      end
    end
  end
end

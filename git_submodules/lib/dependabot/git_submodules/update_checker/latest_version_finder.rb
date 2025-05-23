# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/package/package_latest_version_finder"
require "dependabot/git_submodules/update_checker"
require "dependabot/git_submodules/package/package_details_fetcher"

module Dependabot
  module GitSubmodules
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, credentials:)
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        def version_list
          @version_list ||=
            T.let(Package::PackageDetailsFetcher.new(
              dependency: dependency,
              credentials: credentials
            ).available_versions, T.nilable(String))
        end

        sig { returns(T.nilable(T.any(String, Dependabot::Version))) }
        def latest_version
          @latest_version ||= T.let(version_list, T.nilable(String))
        end
      end
    end
  end
end

# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Elm
      class ElmPackage < Dependabot::UpdateCheckers::Base
        require_relative "elm_package/requirements_updater"
        require_relative "elm_package/version_resolver"

        VERSION_REGEX = /\d+\.\d+\.\d+/
        VERSIONS_LINE_REGEX =
          /versions: \[(?<versions>("#{VERSION_REGEX}",?\s*)+)\]/

        def latest_version
          @latest_version ||=
            all_versions.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }.
            max
        end

        def can_update?(requirements_to_unlock:)
          # We're overriding can_update? bc otherwise
          # there'd be no distinction between :own and :all
          # given the logic in Dependabot::UpdateCheckers::Base
          version_resolver.latest_resolvable_version(
            unlock_requirement: requirements_to_unlock
          )
        end

        def latest_resolvable_version
          version_resolver.latest_resolvable_version(unlock_requirement: :all)
        end

        def latest_resolvable_version_with_no_unlock
          # No concept of "unlocking" for elm-packages
          # Elm-package installs whatever it wants
          # to satisfy the minimum dependencies you set
          #
          # To complicate things more, it's not advised
          # to commit the `exact-dependencies.json` file
          # so no dependency `appears_in_lockfile?`.
          #
          # Given what's in base.rb, I imagine this will
          # never be called
          #
          # Nevertheless, let's leave it the same as
          # dependency.version
          dependency.version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_resolvable_version: latest_resolvable_version
          ).updated_requirements
        end

        private

        def version_resolver
          @version_resolver ||= VersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            versions: all_versions
          )
        end

        def updated_dependencies_after_full_unlock
          version_resolver.
            updated_dependencies_after_full_unlock(latest_resolvable_version)
        end

        def latest_version_resolvable_with_full_unlock?
          # This is never called, but..
          latest_version == latest_resolvable_version
        end

        def all_versions
          return @all_versions if @version_lookup_attempted
          @version_lookup_attempted = true

          response = Excon.get(
            "http://package.elm-lang.org/packages/#{dependency.name}/",
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          return [] unless response.status == 200
          unless response.body.match?(VERSIONS_LINE_REGEX)
            raise "Unexpected response body: #{response.body}"
          end

          response.body.
            match(VERSIONS_LINE_REGEX).
            named_captures.fetch("versions").
            scan(VERSION_REGEX).
            map { |v| version_class.new(v) }.
            sort
        end

        def ignore_reqs
          # Note: we use Gem::Requirement here because ignore conditions will
          # be passed as Ruby ranges
          ignored_versions.map { |req| Gem::Requirement.new(req.split(",")) }
        end
      end
    end
  end
end

# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Elm
      # TODO:
      # * latest_resolvable_version_with_no_unlock: what's the latest version something can go to without modifying elm-package.json?
      # => this probably doesn't make sense for elm but :shrug:
      # => elm-package install, bring back dep modifications, return current version if any diff between exact-dependencies.json <> elm-package.json
      # * latest_resolvable_version: what's the latest version something can go to without modifying other deps in elm-package.json?
      # => elm-package install, bring back dep modifications, return current version if other deps modified
      # => if we could build a map of version dependencies somehow, that'd be awesome.. I wonder what elm-package uses..
      # * latest_version_resolvable_with_full_unlock:
      # => elm-package install, bring back dep modifications, give out latest version
      class ElmPackage < Dependabot::UpdateCheckers::Base
        # require_relative "elm_package/requirements_updater"
        require_relative "elm_package/version_resolver"

        VERSION_REGEX = /(\d+)\.(\d+)\.(\d+)/
        VERSIONS_REGEX = /versions: \[("#{VERSION_REGEX}",?)+\]/
        def latest_version
          versions.last
        end

        def latest_resolvable_version
          # what's the latest version something can go to without modifying other deps in elm-package.json?
          # => elm-package install, bring back dep modifications, return current version if other deps modified
          VersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            unlock_requirement: true,
            versions: versions
          ).latest_resolvable_version
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
          # TODO: Delegate to RequirementsUpdater
          # it should return the .requirements field on Dependency
          # updated to the `latest_resolvable_version`
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
        end

        private

        def updated_dependencies_after_full_unlock
          throw NotImplemented
        end

        def latest_version_resolvable_with_full_unlock?
          # Elm-package doesn't have locking.
          # If we can't upgrade with the other methods
          # it must mean some dependency doesn't yet
          # support `latest_version`.
          #
          # Elm package doesn't let us get to this
          # state unless we manually try to update
          # a requirement.
          false
        end

        def versions
          url = "http://package.elm-lang.org/packages/#{dependency.name}/"

          response = Excon.get(
            url,
            idempotent: true,
            omit_default_port: true,
            middlewares: SharedHelpers.excon_middleware
          )

          return [dependency.version] unless response.status == 200

          matches = VERSIONS_REGEX.match(response.body).to_a

          return [dependency.version] unless matches.any?

          matches[0].scan(VERSION_REGEX).
            map {|strings| strings.map(&:to_i)}.
            sort
        end
      end
    end
  end
end

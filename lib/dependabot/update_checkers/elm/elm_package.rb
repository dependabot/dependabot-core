# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Elm
      class ElmPackage < Dependabot::UpdateCheckers::Base
        VERSION_REGEX = /(\d+)\.(\d+)\.(\d+)/
        VERSIONS_REGEX = /versions: \[("#{VERSION_REGEX}",?)+\]/
        def latest_version
          versions.last
        end

        def latest_resolvable_version
          # TODO: how do we deal with resolvability in elm?
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          # No concept of "unlocking" for elm-packages
          # elm-package sort of on always-unlock mode
          dependency.version
        end

        def updated_requirements

        end

        private

        def updated_dependencies_after_full_unlock
          throw NotImplemented
        end

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't relevant for elm-packages
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

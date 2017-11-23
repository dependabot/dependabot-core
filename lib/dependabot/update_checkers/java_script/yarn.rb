# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class Yarn < Dependabot::UpdateCheckers::Base
        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          # Javascript doesn't have the concept of version conflicts, so the
          # latest version is always resolvable.
          latest_version
        end

        def updated_requirements
          return dependency.requirements unless latest_resolvable_version

          version_regex = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

          updated_requirement =
            dependency.requirements.first[:requirement].
            sub(version_regex) do |old_version|
              old_parts = old_version.split(".")
              parts =
                latest_resolvable_version.to_s.split(".").first(old_parts.count)
              parts.map.with_index do |part, i|
                old_parts[i].match?(/^x\b/) ? "x" : part
              end.join(".")
            end

          [
            dependency.requirements.first.
              merge(requirement: updated_requirement)
          ]
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Yarn (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def fetch_latest_version
          npm_response = Excon.get(
            dependency_url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          # TODO: Hack until credentials are supported. A 404 for a namespaced
          # dependency almost certainly signifies a private registry
          if dependency.name.start_with?("@") && npm_response.status == 404
            return nil
          end

          latest_dist_tag = JSON.parse(npm_response.body)["dist-tags"]["latest"]
          latest_version = Gem::Version.new(latest_dist_tag)
          return latest_version unless latest_version.prerelease?

          latest_full_release =
            JSON.parse(npm_response.body)["versions"].
            keys.map { |v| Gem::Version.new(v) }.
            reject(&:prerelease?).sort.last

          Gem::Version.new(latest_full_release)
        end

        def dependency_url
          # NPM registry expects slashes to be escaped
          path = dependency.name.gsub("/", "%2F")
          "https://registry.npmjs.org/#{path}"
        end
      end
    end
  end
end

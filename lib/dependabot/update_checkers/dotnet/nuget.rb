# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/utils/dotnet/requirement"

module Dependabot
  module UpdateCheckers
    module Dotnet
      class Nuget < Dependabot::UpdateCheckers::Base
        require_relative "nuget/requirements_updater"

        def latest_version
          @latest_version =
            begin
              versions = available_versions
              versions.reject!(&:prerelease?) unless wants_prerelease?
              versions.reject! do |v|
                ignore_reqs.any? { |r| r.satisfied_by?(v) }
              end
              versions.max
            end
        end

        def latest_resolvable_version
          # TODO: Check version resolution!
          latest_version
        end

        def latest_resolvable_version_with_no_unlock
          versions = available_versions
          reqs = dependency.requirements.map do |r|
            reqs = (r.fetch(:requirement) || "").split(",").map(&:strip)
            Utils::Dotnet::Requirement.new(reqs)
          end
          versions.reject!(&:prerelease?) unless wants_prerelease?
          versions.sort.reverse.
            reject { |v| ignore_reqs.any? { |r| r.satisfied_by?(v) } }.
            find { |v| reqs.all? { |r| r.satisfied_by?(v) } }
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            latest_version: latest_version&.to_s
          ).updated_requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Dotnet (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def available_versions
          nuget_listing.
            fetch("versions", []).
            map { |v| version_class.new(v) }
        end

        def wants_prerelease?
          if dependency.version &&
             version_class.new(dependency.version).prerelease?
            return true
          end

          dependency.requirements.any? do |req|
            reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
            reqs.any? { |r| r.include?("-") }
          end
        end

        def ignore_reqs
          ignored_versions.map do |req|
            Utils::Dotnet::Requirement.new(req.split(","))
          end
        end

        def nuget_listing
          return @nuget_listing unless @nuget_listing.nil?

          response = Excon.get(
            dependency_url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          @nuget_listing = JSON.parse(response.body)
        end

        def dependency_url
          "https://api.nuget.org/v3-flatcontainer/"\
          "#{dependency.name.downcase}/index.json"
        end
      end
    end
  end
end

# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/helm/requirements_updater"
require "dependabot/helm/requirement"
require "dependabot/helm/version"

module Dependabot
  module Helm
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_resolvable_version
        # We don't yet support updating indirect dependencies for go_modules
        #
        # To update indirect dependencies we'll need to promote the indirect
        # dependency to the go.mod file forcing the resolver to pick this
        # version (possibly as # indirect)
        unless dependency.top_level?
          return unless dependency.version

          return version_class.new(dependency.version)
        end

        @latest_resolvable_version ||=
          version_class.new(find_latest_resolvable_version)
      end

      def latest_version
        latest_resolvable_version
      end

      def find_latest_resolvable_version
        versions = all_repository_versions
        @latest_resolvable_version = versions.max
      end

      def all_repository_versions
        response = Excon.get(
          "#{dependency.requirements.first[:source]}/index.yaml",
          idempotent: true,
          **SharedHelpers.excon_defaults
        )

        raise "Response from repository was #{response.status}" unless response.status == 200

        Psych.load(response.body).fetch("entries").fetch(dependency.name).map do |release|
          version_class.new(release.fetch("version"))
        end
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: latest_version&.to_s
        ).updated_requirements
      end

      def latest_version_resolvable_with_full_unlock?
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end
    end
  end
end

Dependabot::UpdateCheckers.register("helm", Dependabot::Helm::UpdateChecker)

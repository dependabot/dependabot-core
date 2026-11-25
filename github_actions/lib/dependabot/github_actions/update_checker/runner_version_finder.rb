# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/github_actions/runner_label"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/version"

module Dependabot
  module GithubActions
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      # Works out which image a runner dependency should move to, and rewrites its
      # labels. Runner images don't have release dates or advisories, so cooldown and
      # security updates don't apply.
      class RunnerVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            ignore_requirements: T::Array[Dependabot::Requirement],
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(dependency:, ignore_requirements:, raise_on_ignored:)
          @dependency = dependency
          @ignore_requirements = ignore_requirements
          @raise_on_ignored = raise_on_ignored
        end

        # The newest generally available image in the family, or the current
        # version when every newer one is ignored.
        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          current = @dependency.version
          return unless current && Version.correct?(current)

          current_version = Version.new(current)
          newer = family_versions.select { |version| version > current_version }
          allowed = newer.reject { |version| @ignore_requirements.any? { |req| req.satisfied_by?(version) } }
          raise Dependabot::AllVersionsIgnored if @raise_on_ignored && allowed.empty? && newer.any?

          allowed.max || current_version
        end

        # Moves every label older than `target` to it, keeping the family suffix.
        sig { params(target: String).returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements(target)
          @dependency.requirements.map do |req|
            runner = RunnerLabel.parse(req.metadata_string("declaration_string").to_s)
            next req unless runner && Version.new(target) > Version.new(runner.version)

            metadata = T.must(req.metadata).dup
            key = metadata.key?("declaration_string") ? "declaration_string" : :declaration_string
            metadata[key] = runner.with_version(target)
            Dependabot::DependencyRequirement.create(req.merge(metadata: metadata))
          end
        end

        private

        sig { returns(T::Array[Dependabot::Version]) }
        def family_versions
          RunnerLabel::AVAILABLE_VERSIONS.fetch(@dependency.name, []).map { |version| Version.new(version) }
        end
      end
    end
  end
end

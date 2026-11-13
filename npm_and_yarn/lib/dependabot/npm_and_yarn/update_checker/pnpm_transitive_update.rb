# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/logger"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/pnpm_resolutions"
require "dependabot/npm_and_yarn/version"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      # Runs `pnpm update` for a transitive dependency in the current directory
      # and keeps the result inside the version bound Dependabot selected.
      #
      # The update is pinned to the allowable version. pnpm 11.23+ refuses the
      # pin for a package no manifest declares, which is always the case here,
      # so it is retried without one and pnpm resolves the package as a fresh
      # install would, at every depth. That resolution can land above an
      # ignored or cooling-down version, so a result reached without the pin is
      # checked against the bound edge by edge before it is proposed.
      class PnpmTransitiveUpdate
        extend T::Sig

        sig { params(dependency: Dependency, latest_allowable_version: T.nilable(Gem::Version)).void }
        def initialize(dependency:, latest_allowable_version:)
          @dependency = dependency
          @latest_allowable_version = latest_allowable_version
          @pin_dropped = T.let(false, T::Boolean)
        end

        sig { returns(T::Boolean) }
        attr_reader :pin_dropped

        sig { void }
        def run
          Helpers.run_pnpm_command(command, fingerprint: fingerprint)
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise if Helpers.pnpm_indirect_dependency_names(e.message).empty?

          Dependabot.logger.info("pnpm refused to pin #{@dependency.name}; retrying the update without a version")
          @pin_dropped = true
          Helpers.run_pnpm_command(
            "update #{@dependency.name} --lockfile-only --no-save -r",
            fingerprint: "update <dependency_name> --lockfile-only --no-save -r"
          )
        end

        # Records that a fallback resolved the package without a version.
        sig { void }
        def resolved_without_pin
          @pin_dropped = true
        end

        # Whether `candidate`, and every resolution the update moved or added
        # across the lockfiles, is within the allowable version.
        sig do
          params(
            candidate: Gem::Version,
            before: T::Array[DependencyFile],
            after: T::Array[DependencyFile]
          ).returns(T::Boolean)
        end
        def within_bound?(candidate:, before:, after:)
          allowable = @latest_allowable_version
          return true if allowable.nil?
          return false if candidate > allowable

          after.select { |lockfile| lockfile.name.end_with?("pnpm-lock.yaml") }.all? do |updated|
            original = before.find { |lockfile| lockfile.name == updated.name }
            changed_within?(original&.content || "", updated.content || "", allowable)
          end
        end

        sig { params(original: String, updated: String, allowable: Gem::Version).returns(T::Boolean) }
        def changed_within?(original, updated, allowable)
          PnpmResolutions.changed_versions(original, updated, @dependency.name).all? do |version|
            Version.correct?(version) && Version.new(version) <= allowable
          end
        end

        private

        sig { returns(String) }
        def command
          if @latest_allowable_version
            "update #{@dependency.name}@#{@latest_allowable_version} --lockfile-only --no-save -r"
          else
            "update #{@dependency.name} --lockfile-only"
          end
        end

        sig { returns(String) }
        def fingerprint
          if @latest_allowable_version
            "update <dependency_name>@<latest_allowable_version> --lockfile-only --no-save -r"
          else
            "update <dependency_name> --lockfile-only"
          end
        end
      end
    end
  end
end

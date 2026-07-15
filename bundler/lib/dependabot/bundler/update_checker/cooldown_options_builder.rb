# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/security_advisory"
require "dependabot/package/release_cooldown_options"
require "dependabot/bundler/update_checker"

module Dependabot
  module Bundler
    class UpdateChecker < UpdateCheckers::Base
      # Owns the cooldown policy for Bundler updates: it derives the effective
      # `ReleaseCooldownOptions` from an optional `cooldown:` declared on a Gemfile
      # `source` line and decides when Bundler's native cooldown must be disabled.
      #
      # Extraction is best-effort: it reads the manifest text rather than Bundler's
      # evaluated source config, so uncommon declarations (see SOURCE_COOLDOWN_REGEX
      # and #manifest_files) may be missed or understated. For regular updates
      # Bundler's native cooldown stays enabled as the authoritative backstop, so the
      # worst case is a missed update, never selecting a version native resolution
      # rejects.
      class CooldownOptionsBuilder
        extend T::Sig

        # Matches the common inline `source "<url>", cooldown: <days>` form. Uncommon
        # forms are not handled: a dynamic URL, `cooldown:` on a wrapped line, or a
        # non-literal/underscored value (e.g. `cooldown: 14_000` reads as `14`). Those
        # Gemfiles fall back to Bundler's native cooldown during resolution, so a
        # too-new release is rejected rather than selected — a missed update at worst,
        # never an incorrect version.
        SOURCE_COOLDOWN_REGEX =
          /^\s*source\s*(?:\(\s*)?["'][^"']+["']\s*,[^\n#]*?\bcooldown:\s*(\d+)/

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def initialize(dependency_files:, security_advisories:)
          @dependency_files = dependency_files
          @security_advisories = security_advisories
        end

        # Effective cooldown for target-dependency version selection. Target versions
        # are fetched from the RubyGems API, which Bundler's native cooldown does not
        # gate, so Dependabot applies the source cooldown here. Security updates must
        # never be blocked, so the base config is returned unchanged.
        sig do
          params(base_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions))
            .returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions))
        end
        def release_cooldown_options(base_cooldown)
          return base_cooldown if security_update?

          source_days = source_cooldown_days
          return base_cooldown if source_days.nil? || !source_days.positive?
          return Dependabot::Package::ReleaseCooldownOptions.new(default_days: source_days) if base_cooldown.nil?

          # The Gemfile `source cooldown:` applies uniformly to every candidate version,
          # so treat it as a global floor: max every semver tier with it and drop
          # include/exclude so no dependency can bypass it. Mirrors npm_and_yarn's
          # `merge_cooldown_with_npmrc_floor`.
          Dependabot::Package::ReleaseCooldownOptions.new(
            default_days: [base_cooldown.default_days, source_days].max,
            semver_major_days: [base_cooldown.semver_major_days, source_days].max,
            semver_minor_days: [base_cooldown.semver_minor_days, source_days].max,
            semver_patch_days: [base_cooldown.semver_patch_days, source_days].max,
            include: [],
            exclude: []
          )
        end

        # Options for the native Bundler subprocess. Native cooldown stays enabled for
        # regular updates (per-source, transitive-aware enforcement) and is disabled
        # for security updates so remediation is never blocked.
        sig { params(options: T::Hash[Symbol, T.anything]).returns(T::Hash[Symbol, T.anything]) }
        def native_helper_options(options)
          options.merge(security_updates_only: security_update?)
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Boolean) }
        def security_update?
          @security_advisories.any?
        end

        sig { returns(T.nilable(Integer)) }
        def source_cooldown_days
          manifest_files.flat_map do |file|
            T.must(file.content).scan(SOURCE_COOLDOWN_REGEX).flatten.map { |value| Integer(value, 10) }
          end.max
        end

        # Support files (e.g. child Gemfiles fetched for `eval_gemfile`) and lockfiles
        # are skipped, so a `cooldown:` declared only in an evaled Gemfile is not seen
        # here; Bundler's native cooldown still enforces it during resolution.
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def manifest_files
          dependency_files.reject(&:support_file?)
                          .reject { |file| file.name.end_with?(".lock", ".locked", ".gemspec", ".specification") }
        end
      end
    end
  end
end

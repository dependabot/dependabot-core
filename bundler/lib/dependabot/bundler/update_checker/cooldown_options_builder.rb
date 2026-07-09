# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/package/release_cooldown_options"
require "dependabot/bundler/update_checker"

module Dependabot
  module Bundler
    class UpdateChecker < UpdateCheckers::Base
      # Reads an optional `cooldown:` option declared on a `source` line in the
      # Gemfile and merges it into any cooldown options configured for the update.
      class CooldownOptionsBuilder
        extend T::Sig

        SOURCE_COOLDOWN_REGEX =
          /^\s*source\s*(?:\(\s*)?["'][^"']+["']\s*,[^\n#]*?\bcooldown:\s*(\d+)/

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig do
          params(base_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions))
            .returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions))
        end
        def build(base_cooldown)
          source_days = source_cooldown_days
          return base_cooldown if source_days.nil? || !source_days.positive?
          return Dependabot::Package::ReleaseCooldownOptions.new(default_days: source_days) if base_cooldown.nil?

          Dependabot::Package::ReleaseCooldownOptions.new(
            default_days: [base_cooldown.default_days, source_days].max,
            semver_major_days: base_cooldown.semver_major_days,
            semver_minor_days: base_cooldown.semver_minor_days,
            semver_patch_days: base_cooldown.semver_patch_days,
            include: base_cooldown.include.to_a,
            exclude: base_cooldown.exclude.to_a
          )
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Integer)) }
        def source_cooldown_days
          manifest_files.flat_map do |file|
            T.must(file.content).scan(SOURCE_COOLDOWN_REGEX).flatten.map { |value| Integer(value, 10) }
          end.max
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def manifest_files
          dependency_files.reject(&:support_file?)
                          .reject { |file| file.name.end_with?(".lock", ".locked", ".gemspec", ".specification") }
        end
      end
    end
  end
end

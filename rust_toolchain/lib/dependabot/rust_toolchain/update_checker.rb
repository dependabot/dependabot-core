# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module RustToolchain
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_finder.latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |requirement|
          {
            file: requirement[:file],
            requirement: latest_version,
            groups: requirement[:groups],
            source: requirement[:source]
          }
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(LatestVersionFinder)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("rust_toolchain", Dependabot::RustToolchain::UpdateChecker)

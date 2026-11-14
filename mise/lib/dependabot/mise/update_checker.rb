# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Mise
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        versions = version_updates.values
        versions = latest_versions.values.compact if versions.empty?
        versions.max
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        # mise has no lockfile; the version pinned in mise.toml IS the resolved version.
        # "No unlock" means staying at the current pin.
        dependency.version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        wrap_requirements(
          dependency.requirements.map do |req|
            latest = version_updates[req]
            next req unless latest

            req.merge(
              requirement: latest.to_s,
              metadata: (req.metadata || {}).transform_keys(&:to_sym).merge(resolved_version: latest.to_s)
            )
          end
        )
      end

      sig do
        override
          .params(updated_version: T.any(String, Gem::Version))
          .returns(T.nilable(T.any(String, Gem::Version)))
      end
      def latest_resolvable_previous_version(updated_version)
        version_updates.filter_map do |req, version|
          current_version_for(req) if version.to_s == updated_version.to_s
        end.min || dependency.version
      end

      private

      sig do
        params(versions: T::Hash[Dependabot::DependencyRequirement, T.nilable(Dependabot::Version)])
          .returns(T::Hash[Dependabot::DependencyRequirement, Dependabot::Version])
      end
      def version_updates(versions = latest_versions)
        versions.filter_map do |req, latest|
          current = current_version_for(req)
          [req, latest] if latest && current && latest > current
        end.to_h
      end

      sig { returns(T::Hash[Dependabot::DependencyRequirement, T.nilable(Dependabot::Version)]) }
      def latest_versions
        @latest_versions ||= T.let(
          begin
            ignored = T.let(false, T::Boolean)
            versions = dependency.requirements.to_h do |req|
              [req, latest_version_for(req)]
            rescue Dependabot::AllVersionsIgnored
              ignored = true
              [req, nil]
            end
            raise Dependabot::AllVersionsIgnored if ignored && version_updates(versions).empty?

            versions
          end,
          T.nilable(T::Hash[Dependabot::DependencyRequirement, T.nilable(Dependabot::Version)])
        )
      end

      sig { params(req: Dependabot::DependencyRequirement).returns(T.nilable(Dependabot::Version)) }
      def latest_version_for(req)
        manifest = dependency_files.find { |file| file.name == req.file }
        unless manifest
          raise Dependabot::DependencyFileNotFound.new(
            req.file, "Manifest #{req.file} referenced by #{dependency.name} was not provided"
          )
        end

        scoped_dependency = Dependabot::Dependency.new(
          name: dependency.name,
          version: current_version_for(req)&.to_s || dependency.version,
          requirements: [req],
          package_manager: dependency.package_manager
        )
        LatestVersionFinder.new(
          dependency: scoped_dependency,
          dependency_files: [manifest],
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          security_advisories: security_advisories,
          cooldown_options: update_cooldown
        ).latest_version
      end

      sig { params(req: Dependabot::DependencyRequirement).returns(T.nilable(Dependabot::Version)) }
      def current_version_for(req)
        version = req.metadata_string("resolved_version") || req.requirement_string
        version_class.new(version) if version_class.correct?(version)
      end

      sig { override.returns(T::Boolean) }
      def numeric_version_up_to_date?
        latest_versions.values.all? && version_updates.empty?
      end

      sig { override.params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def numeric_version_can_update?(requirements_to_unlock:)
        return super unless requirements_to_unlock == :own

        version_updates.any?
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        []
      end
    end
  end
end

Dependabot::UpdateCheckers.register("mise", Dependabot::Mise::UpdateChecker)

require_relative "update_checker/latest_version_finder"

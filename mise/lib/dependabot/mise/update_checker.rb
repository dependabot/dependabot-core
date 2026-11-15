# typed: strong
# frozen_string_literal: true

require "dependabot/mise/file_fetcher"
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

      # Use :own so lockfile-only updates retain per-manifest resolved_version metadata.
      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        dependency.version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        wrap_requirements(
          dependency.requirements.map do |req|
            update = planned_update(req, latest_versions[req])
            next req unless update

            requirement, version = update
            req.merge(
              requirement: requirement,
              metadata: (req.metadata || {}).transform_keys(&:to_sym).merge(resolved_version: version.to_s)
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
          update = planned_update(req, latest)
          [req, update.last] if update
        end.to_h
      end

      # The requirement a manifest declares after the update, and the version it then resolves to.
      sig do
        params(req: Dependabot::DependencyRequirement, latest: T.nilable(Dependabot::Version))
          .returns(T.nilable([String, Dependabot::Version]))
      end
      def planned_update(req, latest)
        current = current_version_for(req)
        return unless latest && current && latest > current

        requested = req.requirement_string.to_s
        if version_class.correct?(requested) && !requirements_update_strategy&.lockfile_only?
          requirement = updated_requirement_string(req, latest)
          return [requirement, latest] unless requirement == requested
        end
        lockfile_only_update(req, current)
      end

      # A pin the newer release still satisfies, such as "latest", "lts" or "24", can only move inside the
      # lockfile, to what mise resolves it to, and only if ignore rules and cooldown allow that version.
      sig do
        params(req: Dependabot::DependencyRequirement, current: Dependabot::Version)
          .returns(T.nilable([String, Dependabot::Version]))
      end
      def lockfile_only_update(req, current)
        lockfile_name = Dependabot::Mise::FileFetcher.lockfile_path_for(T.must(req.file))
        return unless dependency_files.any? { |file| file.name == lockfile_name }

        requested = req.requirement_string.to_s
        resolved = finder_for(req).resolved_pin(requested)
        return unless resolved && version_class.correct?(resolved) && finder_for(req).allowed?(resolved)

        version = version_class.new(resolved)
        return unless version > current
        return [requested, version] if bump_keeps_other_requests_allowed?(req, lockfile_name)

        Dependabot.logger.info(
          "Not relocking #{dependency.name} for #{req.file}: mise lock --bump would also move " \
          "another request in #{lockfile_name} to a version that isn't allowed"
        )
        nil
      end

      # mise lock --bump re-resolves every request for the tool that shares the lockfile.
      sig { params(req: Dependabot::DependencyRequirement, lockfile_name: String).returns(T::Boolean) }
      def bump_keeps_other_requests_allowed?(req, lockfile_name)
        dependency.requirements.all? do |other|
          next true if other == req
          next true unless Dependabot::Mise::FileFetcher.lockfile_path_for(T.must(other.file)) == lockfile_name

          resolved = finder_for(other).resolved_pin(other.requirement_string.to_s)
          resolved == current_version_for(other)&.to_s || (!resolved.nil? && finder_for(other).allowed?(resolved))
        end
      end

      # Keep partial pins only when mise resolves them to the selected version.
      # Otherwise pin exactly to preserve ignore rules and cooldown.
      sig { params(req: Dependabot::DependencyRequirement, latest: Dependabot::Version).returns(String) }
      def updated_requirement_string(req, latest)
        requested = req.requirement_string.to_s
        return latest.to_s unless req.metadata_string("resolved_version")&.start_with?("#{requested}.")

        pin = latest.to_s.split(".").first(requested.split(".").length).join(".")
        return pin if pin == requested || finder_for(req).resolved_pin(pin) == latest.to_s

        latest.to_s
      end

      sig { returns(T::Hash[Dependabot::DependencyRequirement, T.nilable(Dependabot::Version)]) }
      def latest_versions
        @latest_versions ||= T.let(
          begin
            ignored = T.let(false, T::Boolean)
            versions = dependency.requirements.to_h do |req|
              [req, finder_for(req).latest_version]
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

      sig { params(req: Dependabot::DependencyRequirement).returns(LatestVersionFinder) }
      def finder_for(req)
        finders = @finders ||= T.let({}, T.nilable(T::Hash[Dependabot::DependencyRequirement, LatestVersionFinder]))
        finders[req] ||= build_finder(req)
      end

      sig { params(req: Dependabot::DependencyRequirement).returns(LatestVersionFinder) }
      def build_finder(req)
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
        )
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

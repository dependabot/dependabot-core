# typed: strong
# frozen_string_literal: true

require "time"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/bazel/version"
require "dependabot/package/package_release"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/registry_client"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(
          fetch_latest_version,
          T.nilable(T.any(String, Gem::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: latest_version.to_s
        ).updated_requirements
      end

      sig { returns(T.class_of(Dependabot::Bazel::Version)) }
      def version_class
        Dependabot::Bazel::Version
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        !latest_version.nil?
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        return [] unless latest_version

        [
          Dependabot::Dependency.new(
            name: dependency.name,
            version: latest_version.to_s,
            requirements: updated_requirements,
            previous_version: dependency.version,
            previous_requirements: dependency.requirements,
            package_manager: dependency.package_manager
          )
        ]
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def fetch_latest_version
        return nil unless registry_client.get_metadata(dependency.name)

        versions = registry_client.all_module_versions(dependency.name)
        return nil if versions.empty?

        filtered_versions = filter_ignored_versions(versions)
        filtered_versions = filter_lower_versions(filtered_versions)
        filtered_versions = apply_cooldown_filter(filtered_versions)
        return nil if filtered_versions.empty?

        latest_version_string = filtered_versions.max_by { |v| version_sort_key(v) }
        return nil unless latest_version_string

        Dependabot::Bazel::Version.new(latest_version_string)
      rescue Dependabot::DependabotError => e
        Dependabot.logger.warn("Failed to fetch latest version for #{dependency.name}: #{e.message}")
        nil
      end

      sig { returns(UpdateChecker::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          UpdateChecker::RegistryClient.new(credentials: credentials),
          T.nilable(UpdateChecker::RegistryClient)
        )
      end

      sig { params(versions: T::Array[String]).returns(T::Array[String]) }
      def filter_ignored_versions(versions)
        filtered = versions.reject do |version_string|
          version = version_class.new(version_string)
          ignore_requirements.any? { |req| req.satisfied_by?(version) }
        end

        if versions.count > filtered.count
          Dependabot.logger.info("Filtered out #{versions.count - filtered.count} ignored versions")
        end

        if raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions).any?
          Dependabot.logger.info("All updates for #{dependency.name} were ignored")
        end

        filtered
      end

      sig { params(versions: T::Array[String]).returns(T::Array[String]) }
      def filter_lower_versions(versions)
        return versions unless dependency.version

        current_version = version_class.new(dependency.version)
        versions.select { |v| version_class.new(v) > current_version }
      end

      sig { params(versions: T::Array[String]).returns(T::Array[String]) }
      def apply_cooldown_filter(versions)
        return versions if should_skip_cooldown?

        sorted_versions = versions.sort_by { |v| version_sort_key(v) }

        filtered_versions = sorted_versions.reject do |version|
          details = publication_detail(version)

          next false unless details&.released_at

          if cooldown_period?(T.must(details.released_at))
            Dependabot.logger.info("Skipping version #{version} due to cooldown period")
            true
          else
            false
          end
        end

        filtered_versions
      end

      sig { params(version: String).returns(T.nilable(Dependabot::Package::PackageRelease)) }
      def publication_detail(version)
        return publication_details[version] if publication_details.key?(version)

        details = get_version_publication_details(version)
        publication_details[version] = details

        details
      end

      sig { params(version: String).returns(T.nilable(Dependabot::Package::PackageRelease)) }
      def get_version_publication_details(version)
        release_date = registry_client.get_version_release_date(dependency.name, version)
        return nil unless release_date

        Dependabot::Package::PackageRelease.new(
          version: Dependabot::Bazel::Version.new(version),
          released_at: release_date,
          latest: false,
          yanked: false,
          url: nil,
          package_type: "bazel"
        )
      end

      sig { returns(T::Hash[String, T.nilable(Dependabot::Package::PackageRelease)]) }
      def publication_details
        @publication_details ||= T.let(
          {},
          T.nilable(T::Hash[String, T.nilable(Dependabot::Package::PackageRelease)])
        )
      end

      sig { params(release_date: Time).returns(T::Boolean) }
      def cooldown_period?(release_date)
        cooldown = update_cooldown
        return false unless cooldown

        cooldown_days = cooldown.default_days
        (Time.now.to_i - release_date.to_i) < (cooldown_days * 24 * 60 * 60)
      end

      sig { returns(T::Boolean) }
      def should_skip_cooldown?
        cooldown = update_cooldown
        cooldown.nil? || !cooldown_enabled? || !cooldown.included?(dependency.name)
      end

      sig { returns(T::Boolean) }
      def cooldown_enabled?
        true
      end

      sig { params(version: String).returns(T::Array[Integer]) }
      def version_sort_key(version)
        cleaned = version.gsub(/^v/, "")
        parts = cleaned.split(".")
        parts.map { |part| part.match?(/^\d+$/) ? part.to_i : 0 }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("bazel", Dependabot::Bazel::UpdateChecker)

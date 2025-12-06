# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "json"
require "excon"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"
require "dependabot/luarocks/version"
require "dependabot/luarocks/requirement"

module Dependabot
  module Luarocks
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      REGISTRY_URL = "https://luarocks.org/manifest.json"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        available_versions.max
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        available_versions.max
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        dependency.version && version_class.correct?(dependency.version) ? version_class.new(dependency.version) : nil
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        # No security advisory data available yet for LuaRocks packages.
        nil
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        target = latest_resolvable_version
        return dependency.requirements unless target

        dependency.requirements.map do |req|
          requirement = updated_requirement_string(req[:requirement], target)
          req.merge(requirement: requirement)
        end
      end

      private

      sig { returns(T::Array[Dependabot::Version]) }
      def available_versions
        @available_versions = T.let(@available_versions, T.nilable(T::Array[Dependabot::Version]))
        return @available_versions unless @available_versions.nil?

        @available_versions = begin
          versions = registry_versions
          versions = filter_ignored_versions(versions)
          Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
            versions,
            security_advisories
          ).sort
        rescue JSON::ParserError, Excon::Error => e
          Dependabot.logger.warn("LuaRocks registry fetch failed: #{e.message}")
          []
        end
      end

      sig { returns(T::Array[Dependabot::Version]) }
      def registry_versions
        response = Excon.get(REGISTRY_URL, idempotent: true, **SharedHelpers.excon_defaults)
        return [] unless response.status.between?(200, 299)

        manifest = JSON.parse(response.body)
        packages = manifest.fetch("repository", {})
        package_versions = packages.fetch(dependency.name, {})

        package_versions.keys.filter_map do |version|
          next unless version_class.correct?(version)

          version_class.new(version)
        end
      end

      sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
      def filter_ignored_versions(versions)
        return versions if ignore_requirements.empty?

        versions.reject do |version|
          ignore_requirements.any? { |req| req.satisfied_by?(version) }
        end
      end

      sig { params(current_requirement: T.nilable(String), target_version: Dependabot::Version).returns(T.nilable(String)) }
      def updated_requirement_string(current_requirement, target_version)
        target = target_version.to_s
        return ">= #{target}" if current_requirement.nil? || current_requirement.strip.empty?

        return current_requirement if current_requirement.include?(target)

        return "= #{target}" unless current_requirement.match?(/\A[<>=~]/)

        current_requirement.sub(/\A([<>=~]+)\s*[^,\s]+/) do
          operator = T.must(Regexp.last_match(1))
          "#{operator.strip} #{target}".strip
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        latest_resolvable_version == latest_version
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        return [] unless latest_resolvable_version

        [updated_dependency_with_own_req_unlock]
      end
    end
  end
end

Dependabot::UpdateCheckers.register("luarocks", Dependabot::Luarocks::UpdateChecker)

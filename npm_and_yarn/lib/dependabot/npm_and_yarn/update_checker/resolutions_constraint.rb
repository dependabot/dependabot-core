# typed: strict
# frozen_string_literal: true

require "json"
require "yaml"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/logger"
require "dependabot/security_advisory"
require "dependabot/package/package_release"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/npm_and_yarn/update_checker"

module Dependabot
  module NpmAndYarn
    class UpdateChecker
      # A yarn `resolutions` / npm `overrides` / pnpm `overrides` entry pins the
      # resolved version of a dependency across the whole tree. When one
      # constrains the dependency we are checking (e.g. `"react-dom": "^18"`),
      # versions outside that constraint can never be installed, so proposing
      # them only produces a spurious NoChangeError when the file updater runs.
      # This encapsulates reading those entries and testing candidate versions
      # against them.
      #
      # Only *immutable, project-wide* constraints are considered:
      # * Entries the file updater rewrites alongside the dependency (an exact
      #   pin matching the current version/requirement, e.g. `"undici": "6.23.0"`)
      #   are ignored, since those updates are realizable. See
      #   `PackageJsonUpdater#matching_resolutions`.
      # * Only globally-applicable selectors (`name` or `**/name`) are honored;
      #   parent-scoped yarn selectors like `parent/name` only constrain nested
      #   copies and must not suppress a realizable top-level update.
      class ResolutionsConstraint
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(dependency:, dependency_files:)
          @dependency = dependency
          @dependency_files = dependency_files
          @requirements = T.let(nil, T.nilable(T::Array[T::Array[Dependabot::NpmAndYarn::Requirement]]))
          @updatable_values = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { returns(T::Boolean) }
        def any?
          requirements.any?
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def satisfied_by?(version)
          requirements.all? do |requirement_array|
            requirement_array.any? { |req| req.satisfied_by?(version) }
          end
        end

        # Versions the constraint filters out that would otherwise fix a
        # security advisory. Used to warn when a resolution/override silently
        # blocks a security update.
        sig do
          params(
            releases: T::Array[Dependabot::Package::PackageRelease],
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).returns(T::Array[Dependabot::Version])
        end
        def suppressed_security_fixes(releases, security_advisories)
          return [] if security_advisories.empty?

          releases.map(&:version)
                  .reject { |version| satisfied_by?(version) }
                  .reject { |version| security_advisories.any? { |advisory| advisory.vulnerable?(version) } }
        end

        # Emits the info/warn logging for a filtering pass: how many versions the
        # constraint removed, and (louder) if any of them would have fixed a
        # security advisory.
        sig do
          params(
            releases: T::Array[Dependabot::Package::PackageRelease],
            filtered: T::Array[Dependabot::Package::PackageRelease],
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def log_filtered(releases, filtered, security_advisories)
          removed = releases.count - filtered.count
          return if removed.zero?

          Dependabot.logger.info("Filtered out #{removed} versions excluded by resolutions/overrides")
          warn_if_suppressing_security_fix(releases, security_advisories)
        end

        # A resolution/override can pin a dependency below its lowest safe
        # version, silently blocking a security fix. Surface a warning so the
        # suppression is observable rather than looking like a spurious no-op.
        sig do
          params(
            releases: T::Array[Dependabot::Package::PackageRelease],
            security_advisories: T::Array[Dependabot::SecurityAdvisory]
          ).void
        end
        def warn_if_suppressing_security_fix(releases, security_advisories)
          fixes = suppressed_security_fixes(releases, security_advisories)
          return if fixes.empty?

          Dependabot.logger.warn(
            "Security fix versions #{fixes.join(', ')} are blocked by a resolutions/overrides " \
            "constraint and cannot be applied automatically"
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T::Array[Dependabot::NpmAndYarn::Requirement]]) }
        def requirements
          @requirements ||= parse_requirements
        end

        sig { returns(T::Array[T::Array[Dependabot::NpmAndYarn::Requirement]]) }
        def parse_requirements
          constraint_values.filter_map do |value|
            reqs = NpmAndYarn::Requirement.requirements_array(value)
            reqs unless reqs.empty?
          end
        rescue Gem::Requirement::BadRequirementError
          []
        end

        sig { returns(T::Array[String]) }
        def constraint_values
          manifest_constraint_values + pnpm_workspace_constraint_values
        end

        sig { returns(T::Array[String]) }
        def manifest_constraint_values
          content = root_manifest&.content
          return [] unless content

          parsed = JSON.parse(content)
          return [] unless parsed.is_a?(Hash)

          extract_matching(override_entries(parsed))
        rescue JSON::ParserError
          []
        end

        # Modern pnpm projects declare root overrides in pnpm-workspace.yaml
        # rather than the package.json `pnpm.overrides` field.
        sig { returns(T::Array[String]) }
        def pnpm_workspace_constraint_values
          content = pnpm_workspace_file&.content
          return [] unless content

          parsed = YAML.safe_load(content, aliases: true)
          return [] unless parsed.is_a?(Hash)

          extract_matching(parsed["overrides"])
        rescue Psych::Exception
          []
        end

        # Selects the override field honored by the detected package manager.
        # npm ignores `resolutions`, Yarn ignores npm `overrides`, and pnpm reads
        # `pnpm.overrides`, so we must not blindly apply whichever field appears.
        sig { params(parsed: T::Hash[String, Object]).returns(Object) }
        def override_entries(parsed)
          case package_manager
          when :pnpm then pnpm_overrides(parsed)
          when :npm then parsed["overrides"]
          when :yarn then parsed["resolutions"]
          else parsed["resolutions"] || parsed["overrides"] || pnpm_overrides(parsed)
          end
        end

        sig { params(parsed: T::Hash[String, Object]).returns(Object) }
        def pnpm_overrides(parsed)
          pnpm = parsed["pnpm"]
          return nil unless pnpm.is_a?(Hash)

          pnpm["overrides"]
        end

        sig { params(entries: Object).returns(T::Array[String]) }
        def extract_matching(entries)
          return [] unless entries.is_a?(Hash)

          entries.filter_map do |key, raw_value|
            next unless key.is_a?(String) && key_matches?(key)

            value = constraint_value(raw_value)
            # Skip entries the updater rewrites alongside the dependency; those
            # updates are realizable and must not be filtered out.
            next if value.nil? || updatable_values.include?(value)

            value
          end
        end

        # npm supports object-valued overrides, where the `.` key overrides the
        # dependency itself (e.g. `"foo": { ".": "1.6.0" }`). Yarn/pnpm use flat
        # string values.
        sig { params(raw_value: Object).returns(T.nilable(String)) }
        def constraint_value(raw_value)
          case raw_value
          when String then raw_value
          when Hash
            nested = raw_value["."]
            nested if nested.is_a?(String)
          end
        end

        sig { returns(T::Array[String]) }
        def updatable_values
          @updatable_values ||= begin
            values = []
            current = dependency.version
            values << current if current
            dependency.requirements.each do |req|
              requirement = req[:requirement]
              values << requirement if requirement.is_a?(String)
            end
            values
          end
        end

        # Only globally-applicable selectors constrain the dependency everywhere.
        # A parent-scoped selector (`parent/name`) only affects nested copies, so
        # treating it as global could suppress a realizable top-level update.
        sig { params(key: String).returns(T::Boolean) }
        def key_matches?(key)
          key == dependency.name || key == "**/#{dependency.name}"
        end

        # Override settings are only honored at the install root, so we ignore
        # nested workspace manifests to avoid a workspace-level override
        # incorrectly capping the whole project.
        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_manifest
          dependency_files.find { |file| file.name == "package.json" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pnpm_workspace_file
          dependency_files.find { |file| file.name == "pnpm-workspace.yaml" }
        end

        sig { returns(Symbol) }
        def package_manager
          return :pnpm if lockfile?("pnpm-lock.yaml") || pnpm_workspace_file
          return :npm if lockfile?("package-lock.json") || lockfile?("npm-shrinkwrap.json")
          return :yarn if lockfile?("yarn.lock")

          :unknown
        end

        sig { params(name: String).returns(T::Boolean) }
        def lockfile?(name)
          dependency_files.any? { |file| file.name == name || file.name.end_with?("/#{name}") }
        end
      end
    end
  end
end

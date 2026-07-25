# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/logger"
require "dependabot/security_advisory"

require "dependabot/vcpkg"
require "dependabot/vcpkg/manifest_baseline"
require "dependabot/vcpkg/package/versions_database"
require "dependabot/vcpkg/requirement"
require "dependabot/vcpkg/update_checker"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      # Works out how to move a vulnerable port onto a safe version.
      #
      # vcpkg offers three levers, tried in this order:
      #
      #   1. raise the registry baseline, which lifts the version floor for every port
      #   2. raise (or add) the port's own `version>=` constraint
      #   3. pin the port with an `overrides` entry, for when the safe version uses a scheme vcpkg
      #      refuses to compare against the one currently selected
      #
      # A safe floor always fixes the port on its own, because it sits above the current version,
      # which in turn already satisfies any declared constraint. Levers 2 and 3 therefore only come
      # up when no release carries the fix, and in that case there is no baseline worth moving to.
      class SecurityFixResolver
        extend T::Sig

        class Fix < T::Struct
          const :version, Dependabot::Vcpkg::Version
          # `:baseline`, `:version_constraint` or `:override`.
          const :kind, Symbol
          const :baseline_tag, T.nilable(String)
          const :baseline_commit_sha, T.nilable(String)
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            ignored_versions: T::Array[String],
            lowest_comparable_version: T.nilable(Dependabot::Version),
            versions_database: Dependabot::Vcpkg::Package::VersionsDatabase
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          security_advisories:,
          ignored_versions:,
          lowest_comparable_version:,
          versions_database: Dependabot::Vcpkg::Package::VersionsDatabase.new
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @security_advisories = security_advisories
          @ignored_versions = ignored_versions
          @lowest_comparable_version = lowest_comparable_version
          @versions_database = versions_database

          @fix = T.let(nil, T.nilable(Fix))
          @resolved = T.let(false, T::Boolean)
          @safe_baseline = T.let(nil, T.nilable([String, Dependabot::Vcpkg::Version]))
          @searched_baseline = T.let(false, T::Boolean)
        end

        sig { returns(T.nilable(Fix)) }
        def fix
          return @fix if @resolved

          @resolved = true
          @fix = resolve
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :lowest_comparable_version

        sig { returns(Dependabot::Vcpkg::Package::VersionsDatabase) }
        attr_reader :versions_database

        sig { returns(T.nilable(Fix)) }
        def resolve
          return nil unless current_version
          return nil if security_advisories.none?

          baseline = safe_baseline
          if baseline && baseline_alone_resolves?(baseline.last)
            return build_baseline_fix(version: baseline.last, tag: baseline.first)
          end

          # The later levers deliberately leave the baseline alone. A safe floor that does not
          # resolve the port on its own is one vcpkg cannot compare against the declared
          # constraint, so moving it as well would only produce a manifest vcpkg rejects.
          constraint_version = comparable_fix_version
          return build_fix(version: constraint_version, kind: :version_constraint) if constraint_version

          override_version = next_safe_published_version
          return nil unless override_version

          build_fix(version: override_version, kind: :override)
        end

        sig { params(version: Dependabot::Vcpkg::Version, kind: Symbol).returns(Fix) }
        def build_fix(version:, kind:)
          Fix.new(version: version, kind: kind, baseline_tag: nil, baseline_commit_sha: nil)
        end

        # A baseline remediation is only worth reporting if the commit it names can be resolved,
        # otherwise the file updater has nothing to write and the run produces an empty pull
        # request.
        sig { params(version: Dependabot::Vcpkg::Version, tag: String).returns(T.nilable(Fix)) }
        def build_baseline_fix(version:, tag:)
          commit_sha = versions_database.commit_sha_for(tag)
          return nil unless commit_sha

          Fix.new(version: version, kind: :baseline, baseline_tag: tag, baseline_commit_sha: commit_sha)
        end

        # The oldest release tag at or after the manifest's baseline whose version floor for this
        # port is safe.
        sig { returns(T.nilable([String, Dependabot::Vcpkg::Version])) }
        def safe_baseline
          return @safe_baseline if @searched_baseline

          @searched_baseline = true
          @safe_baseline = search_safe_baseline
        end

        sig { returns(T.nilable([String, Dependabot::Vcpkg::Version])) }
        def search_safe_baseline
          return nil unless baseline_ref

          # A port's floor generally only moves forwards, but advisories enumerate affected versions
          # rather than describing ranges, so a safe floor can be followed by a vulnerable one. That
          # rules out bisection. The candidate list is bounded by the number of vcpkg releases since
          # the baseline, so scanning it in order is cheap enough.
          upgrade_tags.each do |tag|
            version = safe_baseline_version_for(tag)
            return [tag, version] if version
          end

          nil
        end

        sig { params(tag: String).returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def safe_baseline_version_for(tag)
          current = T.must(current_version)
          version = versions_database.baseline_version_for(port: dependency.name, ref: tag)
          return nil unless version
          # `#<=>` invents an order for incomparable schemes, so ask vcpkg's question first rather
          # than deciding "is this an upgrade" from lexical text ordering.
          return nil unless version.comparable_with?(current)
          return nil unless version > current
          return nil unless safe?(version)

          version
        end

        # Release tags that contain the manifest's current baseline, so a fix never moves it back.
        sig { returns(T::Array[String]) }
        def upgrade_tags
          ref = baseline_ref
          return [] unless ref

          tags = versions_database.release_tags
          index = tags.bsearch_index { |tag| versions_database.ancestor?(ancestor: ref, descendant: tag) }
          return [] unless index

          T.must(tags[index..])
        end

        # True when raising the baseline is enough on its own, i.e. no declared constraint holds
        # the port back at a vulnerable version.
        sig { params(baseline_version: Dependabot::Vcpkg::Version).returns(T::Boolean) }
        def baseline_alone_resolves?(baseline_version)
          declared = declared_constraint_version
          return true unless declared
          return false unless declared.comparable_with?(baseline_version)

          declared <= baseline_version
        end

        sig { returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def comparable_fix_version
          version = lowest_comparable_version
          return nil unless version.is_a?(Dependabot::Vcpkg::Version)

          version
        end

        # When no safe version shares a scheme with the current one, vcpkg can only be pointed at a
        # version with an `overrides` entry. Publication order is the only ordering left, so this
        # takes the earliest safe version published after the current one.
        sig { returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def next_safe_published_version
          current = T.must(current_version)
          published = versions_database.versions_for(dependency.name).map(&:version)
          current_index = published.index { |version| version.eql?(current) }
          # Without knowing where the current version sits, "published after it" is meaningless and
          # picking anything risks pinning the port to an older version than it already uses.
          return nil unless current_index

          T.must(published[0...current_index]).reverse.find do |version|
            # Publishing order is not version order: a backport can appear after a newer release.
            # Where vcpkg can compare the two, refuse to pin the port backwards.
            next false if version.comparable_with?(current) && version <= current

            safe?(version)
          end
        end

        sig { params(version: Dependabot::Vcpkg::Version).returns(T::Boolean) }
        def safe?(version)
          return false if ignored?(version)

          security_advisories.none? { |advisory| advisory.vulnerable?(version) }
        end

        sig { params(version: Dependabot::Vcpkg::Version).returns(T::Boolean) }
        def ignored?(version)
          ignore_requirements.any? { |requirement| requirement.satisfied_by?(version) }
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_requirements
          @ignore_requirements ||= T.let(
            ignored_versions.flat_map { |req| Dependabot::Vcpkg::Requirement.requirements_array(req) },
            T.nilable(T::Array[Dependabot::Requirement])
          )
        end

        sig { returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def declared_constraint_version
          return @declared_constraint_version if @declared_constraint_version

          constraint = dependency.requirements.filter_map { |req| req[:requirement] }.first
          return nil unless constraint.is_a?(String)

          text = constraint.delete_prefix(">=").strip
          return nil unless Dependabot::Vcpkg::Version.correct?(text)

          @declared_constraint_version = T.let(
            Dependabot::Vcpkg::Version.new(text),
            T.nilable(Dependabot::Vcpkg::Version)
          )
        end

        sig { returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def current_version
          return @current_version if @looked_up_current_version

          @looked_up_current_version = T.let(true, T.nilable(T::Boolean))
          version = dependency.version
          @current_version = T.let(
            version && Dependabot::Vcpkg::Version.correct?(version) ? Dependabot::Vcpkg::Version.new(version) : nil,
            T.nilable(Dependabot::Vcpkg::Version)
          )
        end

        sig { returns(T.nilable(String)) }
        def baseline_ref
          @baseline_ref ||= T.let(
            Dependabot::Vcpkg::ManifestBaseline.new(dependency_files:).ref,
            T.nilable(String)
          )
        end
      end
    end
  end
end

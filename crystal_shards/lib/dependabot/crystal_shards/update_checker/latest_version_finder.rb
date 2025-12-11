# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/crystal_shards/update_checker"
require "dependabot/crystal_shards/version"
require "dependabot/crystal_shards/requirement"
require "dependabot/git_commit_checker"
require "dependabot/package/release_cooldown_options"

module Dependabot
  module CrystalShards
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          cooldown_options: nil,
          raise_on_ignored: false
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
          @cooldown_options = cooldown_options
          @raise_on_ignored = raise_on_ignored
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          @latest_version ||= T.let(
            fetch_latest_version,
            T.nilable(Dependabot::Version)
          )
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_security_fix_version
          @lowest_security_fix_version ||= T.let(
            fetch_lowest_security_fix_version,
            T.nilable(Dependabot::Version)
          )
        end

        sig { returns(T.nilable(Time)) }
        def latest_version_release_date
          return nil unless git_dependency?

          tag = git_commit_checker.local_tag_for_latest_version
          return nil unless tag

          tag[:commit_date]
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_latest_version
          return nil if path_dependency?

          versions = available_versions
          versions = filter_ignored_versions(versions)
          versions = filter_cooldown_versions(versions) if cooldown_options
          versions = filter_prerelease_versions(versions) unless wants_prerelease?

          versions.max
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_lowest_security_fix_version
          return nil if path_dependency?
          return nil unless vulnerable?

          versions = available_versions
          versions = filter_ignored_versions(versions)
          versions = filter_vulnerable_versions(versions)
          versions = filter_prerelease_versions(versions) unless wants_prerelease?

          versions.min
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def available_versions
          return [] if path_dependency?

          if git_dependency?
            git_tags_as_versions
          else
            []
          end
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def git_tags_as_versions
          git_commit_checker.local_tags_for_allowed_versions.filter_map do |tag|
            tag_name = tag[:tag]
            next unless tag_name

            version_string = tag_name.gsub(/^v/, "")
            next unless version_class.correct?(version_string)

            version_class.new(version_string)
          end
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_ignored_versions(versions)
          filtered = versions.reject do |v|
            ignore_requirements.any? { |r| r.satisfied_by?(v) }
          end

          raise Dependabot::AllVersionsIgnored if raise_on_ignored && filtered.empty? && versions.any?

          filtered
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_cooldown_versions(versions)
          return versions unless cooldown_options

          versions.reject do |version|
            release_date = release_date_for_version(version)
            next false unless release_date

            in_cooldown_period?(version, release_date)
          end
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_prerelease_versions(versions)
          versions.reject(&:prerelease?)
        end

        sig { params(versions: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_vulnerable_versions(versions)
          versions.reject do |v|
            security_advisories.any? { |a| a.vulnerable?(v) }
          end
        end

        sig { params(version: Dependabot::Version).returns(T.nilable(Time)) }
        def release_date_for_version(version)
          return nil unless git_dependency?

          version_release_dates[version.to_s]
        end

        sig { returns(T::Hash[String, Time]) }
        def version_release_dates
          @version_release_dates ||= T.let(build_version_release_dates, T.nilable(T::Hash[String, Time]))
        end

        sig { returns(T::Hash[String, Time]) }
        def build_version_release_dates
          dates = {}

          git_commit_checker.local_tags_for_allowed_versions.each do |tag|
            tag_name = tag[:tag]
            next unless tag_name

            version_string = tag_name.gsub(/^v/, "")
            next unless version_class.correct?(version_string)

            commit_date = tag[:commit_date]
            dates[version_string] = commit_date if commit_date
          end

          dates
        end

        sig { params(version: Dependabot::Version, release_date: Time).returns(T::Boolean) }
        def in_cooldown_period?(version, release_date)
          return false unless cooldown_options

          current_version = dependency.numeric_version
          return false unless current_version

          semver_type = determine_semver_type(current_version, version)
          cooldown_days = cooldown_days_for_type(semver_type)

          return false if cooldown_days.zero?

          Time.now - release_date < cooldown_days * 24 * 60 * 60
        end

        sig { params(current: Dependabot::Version, new_version: Dependabot::Version).returns(Symbol) }
        def determine_semver_type(current, new_version)
          current_segments = current.segments
          new_segments = new_version.segments

          if new_segments[0] != current_segments[0]
            :major
          elsif new_segments[1] != current_segments[1]
            :minor
          else
            :patch
          end
        end

        sig { params(semver_type: Symbol).returns(Integer) }
        def cooldown_days_for_type(semver_type)
          opts = cooldown_options
          return 0 unless opts

          case semver_type
          when :major
            opts.semver_major_days
          when :minor
            opts.semver_minor_days
          when :patch
            opts.semver_patch_days
          else
            opts.default_days
          end
        end

        sig { returns(T::Array[Dependabot::CrystalShards::Requirement]) }
        def ignore_requirements
          ignored_versions.filter_map do |req_string|
            Dependabot::CrystalShards::Requirement.new(req_string.split(",").map(&:strip))
          rescue Gem::Requirement::BadRequirementError
            nil
          end
        end

        sig { returns(T::Boolean) }
        def vulnerable?
          return false unless dependency.version

          security_advisories.any? do |advisory|
            advisory.vulnerable?(version_class.new(dependency.version))
          end
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return true if dependency.numeric_version&.prerelease?

          dependency.requirements.any? do |req|
            req_string = req.fetch(:requirement) || ""
            req_string.match?(/[a-zA-Z]/)
          end
        end

        sig { returns(T::Boolean) }
        def git_dependency?
          git_commit_checker.git_dependency?
        end

        sig { returns(T::Boolean) }
        def path_dependency?
          dependency.source_type == "path"
        end

        sig { returns(GitCommitChecker) }
        def git_commit_checker
          @git_commit_checker ||= T.let(
            GitCommitChecker.new(
              dependency: dependency,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored
            ),
            T.nilable(GitCommitChecker)
          )
        end

        sig { returns(T.class_of(Dependabot::CrystalShards::Version)) }
        def version_class
          Dependabot::CrystalShards::Version
        end
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/go_modules/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/requirement"
require "dependabot/go_modules/resolvability_errors"

module Dependabot
  module GoModules
    class UpdateChecker
      class LatestVersionFinder
        extend T::Sig

        RESOLVABILITY_ERROR_REGEXES = T.let(
          [
            # Package url/proxy doesn't include any redirect meta tags
            /no go-import meta tags/,
            # Package url 404s
            /404 Not Found/,
            /Repository not found/,
            /unrecognized import path/,
            /malformed module path/,
            # (Private) module could not be fetched
            /module .*: git ls-remote .*: exit status 128/m
          ].freeze,
          T::Array[Regexp]
        )
        # The module was retracted from the proxy
        # OR the version of Go required is greater than what Dependabot supports
        # OR other go.mod version errors
        INVALID_VERSION_REGEX = /(go: loading module retractions for)|(version "[^"]+" invalid)/m
        PSEUDO_VERSION_REGEX = /\b\d{14}-[0-9a-f]{12}$/

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            goprivate: String,
            raise_on_ignored: T::Boolean
          )
            .void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          goprivate:,
          raise_on_ignored: false
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored
          @goprivate           = goprivate
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_version
          @latest_version ||= T.let(fetch_latest_version, T.nilable(Dependabot::Version))
        end

        sig { returns(Dependabot::Version) }
        def lowest_security_fix_version
          @lowest_security_fix_version ||= T.let(fetch_lowest_security_fix_version, T.nilable(Dependabot::Version))
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

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_latest_version
          candidate_versions = available_versions
          candidate_versions = filter_prerelease_versions(candidate_versions)
          candidate_versions = filter_ignored_versions(candidate_versions)
          # Adding the psuedo-version to the list to avoid downgrades
          candidate_versions << version_class.new(dependency.version) if PSEUDO_VERSION_REGEX.match?(dependency.version)

          candidate_versions.max
        end

        sig { returns(Dependabot::Version) }
        def fetch_lowest_security_fix_version
          relevant_versions = available_versions
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(relevant_versions,
                                                                                                    security_advisories)
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          T.must(relevant_versions.min)
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def available_versions
          @available_versions ||= T.let(fetch_available_versions, T.nilable(T::Array[Dependabot::Version]))
        end

        sig { returns(T::Array[Dependabot::Version]) }
        def fetch_available_versions
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              manifest = parse_manifest

              # Set up an empty go.mod so 'go list -m' won't attempt to download dependencies. This
              # appears to be a side effect of operating with modules included in GOPRIVATE. We'll
              # retain any exclude directives to omit those versions.
              File.write("go.mod", "module dummy\n")
              manifest["Exclude"]&.each do |r|
                SharedHelpers.run_shell_command("go mod edit -exclude=#{r['Path']}@#{r['Version']}")
              end

              # Turn off the module proxy for private dependencies
              env = { "GOPRIVATE" => @goprivate }

              versions_json = SharedHelpers.run_shell_command(
                "go list -m -versions -json #{dependency.name}",
                fingerprint: "go list -m -versions -json <dependency_name>",
                env: env
              )
              version_strings = JSON.parse(versions_json)["Versions"]

              return [version_class.new(dependency.version)] if version_strings.nil?

              version_strings.select { |v| version_class.correct?(v) }
                             .map { |v| version_class.new(v) }
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          retry if transitory_failure?(e) && retry_count < 2

          ResolvabilityErrors.handle(e.message, goprivate: @goprivate)
        end

        sig { params(error: StandardError).returns(T::Boolean) }
        def transitory_failure?(error)
          return true if error.message.include?("EOF")

          error.message.include?("Internal Server Error")
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def go_mod
          @go_mod ||= T.let(dependency_files.find { |f| f.name == "go.mod" }, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parse_manifest
          SharedHelpers.in_a_temporary_directory do
            File.write("go.mod", T.must(go_mod).content)
            json = SharedHelpers.run_shell_command("go mod edit -json")

            JSON.parse(json) || {}
          end
        end

        sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_prerelease_versions(versions_array)
          return versions_array if wants_prerelease?

          filtered = versions_array.reject(&:prerelease?)
          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} pre-release versions")
          end
          filtered
        end

        sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_lower_versions(versions_array)
          return versions_array unless dependency.numeric_version

          versions_array
            .select { |version| version > dependency.numeric_version }
        end

        sig { params(versions_array: T::Array[Dependabot::Version]).returns(T::Array[Dependabot::Version]) }
        def filter_ignored_versions(versions_array)
          filtered = versions_array
                     .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
          if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
            raise AllVersionsIgnored
          end

          if versions_array.count > filtered.count
            Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} ignored versions")
          end

          filtered
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          @wants_prerelease ||= T.let(
            begin
              current_version = dependency.numeric_version
              !current_version&.prerelease?.nil?
            end,
            T.nilable(T::Boolean)
          )
        end

        sig { returns(T::Array[Dependabot::Requirement]) }
        def ignore_requirements
          ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end
      end
    end
  end
end

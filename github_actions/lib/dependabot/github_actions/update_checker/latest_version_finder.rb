# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/github_actions/file_parser"
require "dependabot/github_actions/package/package_details_fetcher"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/update_checker"
require "dependabot/github_actions/helpers"
require "dependabot/package/package_latest_version_finder"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module GithubActions
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean,
            options: T::Hash[Symbol, T.untyped],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored:,
          options: {},
          cooldown_options: nil
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored
          @options             = options
          @cooldown_options = cooldown_options

          @git_helper = T.let(git_helper, Dependabot::GithubActions::Helpers::Githelper)
          super
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options
        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories
        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def latest_release
          release = available_release
          return nil unless release

          Dependabot.logger.info("Available release version/ref is #{release}")

          release = cooldown_filter(release)
          if release.nil?
            Dependabot.logger.info("Returning current version/ref (no viable filtered release) #{current_version}")
            return current_version
          end

          release
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def lowest_security_fix_release
          available_security_fix_releases
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          available_latest_version_tag
        end

        private

        sig { returns(T.nilable(Dependabot::GithubActions::Package::PackageDetailsFetcher)) }
        def package_details_fetcher
          @package_details_fetcher = T.let(Dependabot::GithubActions::Package::PackageDetailsFetcher
            .new(
              dependency: dependency,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              security_advisories: security_advisories
            ), T.nilable(Dependabot::GithubActions::Package::PackageDetailsFetcher))
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def available_release
          @available_release = T.let(T.must(package_details_fetcher).release_list_for_git_dependency,
                                     T.nilable(T.any(Dependabot::Version, String)))
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def available_security_fix_releases
          @available_security_fix_releases = T.let(T.must(package_details_fetcher).lowest_security_fix_version_tag,
                                                   T.nilable(T::Hash[Symbol, T.untyped]))
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def available_latest_version_tag
          @latest_version_tag = T.let(T.must(package_details_fetcher).latest_version_tag,
                                      T.nilable(T::Hash[Symbol, T.untyped]))
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_github_actions)
        end

        sig do
          params(release: T.nilable(T.any(Dependabot::Version, String)))
            .returns(T.nilable(T.any(Dependabot::Version, String)))
        end
        def cooldown_filter(release)
          return release unless cooldown_enabled?
          return release unless cooldown_options

          Dependabot.logger.info("Initializing cooldown filter")
          release_date = commit_metadata_details

          unless release_date
            Dependabot.logger.info("No release date found, skipping cooldown filtering")
            return release
          end

          if release_in_cooldown_period?(Time.parse(release_date))
            Dependabot.logger.info("Filtered out (cooldown) #{dependency.name}, #{release}")
            return nil
          end

          release
        end

        sig { returns(T.nilable(String)) }
        def commit_metadata_details
          @commit_metadata_details ||= T.let(
            begin
              url = @git_helper.git_commit_checker.dependency_source_details&.fetch(:url)
              source = T.must(Source.from_url(url))

              SharedHelpers.in_a_temporary_directory(File.dirname(source.repo)) do |temp_dir|
                repo_contents_path = File.join(temp_dir, File.basename(source.repo))

                SharedHelpers.run_shell_command("git clone --bare --no-recurse-submodules #{url} #{repo_contents_path}")
                Dir.chdir(repo_contents_path) do
                  date = SharedHelpers.run_shell_command("git show --no-patch --format=\"%cd\" " \
                                                         "--date=iso #{commit_ref}")
                  Dependabot.logger.info("Found release date : #{Time.parse(date)}")
                  return date
                end
              end
            rescue StandardError => e
              Dependabot.logger.error("Error (github actions) while checking release date for #{dependency.name}")
              Dependabot.logger.error(e.message)

              nil
            end,
            T.nilable(String)
          )
        end

        sig { params(release_date: Time).returns(T::Boolean) }
        def release_in_cooldown_period?(release_date)
          cooldown = @cooldown_options

          return false unless T.must(cooldown).included?(dependency.name)

          days = T.must(cooldown).default_days
          passed_seconds = Time.now.to_i - release_date.to_i

          Dependabot.logger.info("Days since release : #{passed_seconds / (3600 * 24)} " \
                                 "(cooldown days #{T.must(cooldown_options).default_days})")

          passed_seconds < days * DAY_IN_SECONDS
        end

        sig { returns(String) }
        def commit_ref
          latest_version_tag&.fetch(:commit_sha)
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def current_version
          return dependency.source_details(allowed_types: ["git"])&.fetch(:ref) if release_type_sha?

          T.let(dependency.numeric_version, T.nilable(Dependabot::Version))
        end

        sig { returns(T::Boolean) }
        def release_type_sha?
          available_release.is_a?(String)
        end

        sig { returns(Dependabot::GithubActions::Helpers::Githelper) }
        def git_helper
          Helpers::Githelper.new(dependency: dependency, credentials: credentials,
                                 ignored_versions: ignored_versions, raise_on_ignored: raise_on_ignored,
                                 consider_version_branches_pinned: false, dependency_source_details: nil)
        end
      end
    end
  end
end

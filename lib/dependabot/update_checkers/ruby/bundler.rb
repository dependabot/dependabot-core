# frozen_string_literal: true

require "bundler_definition_version_patch"
require "bundler_git_source_patch"
require "excon"
require "gems"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        require "dependabot/update_checkers/ruby/bundler/file_preparer"
        require "dependabot/update_checkers/ruby/bundler/requirements_updater"

        GIT_REF_REGEX = /git reset --hard [^\s]*` in directory (?<path>[^\s]*)/

        def latest_version
          return latest_version_details&.fetch(:version) unless git_dependency?

          unless git_commit_checker.pinned?
            return latest_version_details.fetch(:commit_sha)
          end

          latest_version = latest_version_details.fetch(:version)
          if git_commit_checker.commit_in_released_version?(latest_version)
            return latest_version_details.fetch(:version)
          end

          dependency.version
        end

        def latest_resolvable_version
          unless git_dependency?
            return latest_resolvable_version_details&.fetch(:version)
          end

          unless git_commit_checker.pinned?
            return latest_resolvable_version_details.fetch(:commit_sha)
          end

          latest_version = latest_resolvable_version_details.fetch(:version)
          if git_commit_checker.commit_in_released_version?(latest_version)
            return latest_resolvable_version_details.fetch(:version)
          end

          dependency.version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            existing_version: dependency.version,
            remove_git_source: should_switch_source_from_git_to_rubygems?,
            latest_version: latest_version_details&.fetch(:version)&.to_s,
            latest_resolvable_version:
              latest_resolvable_version_details&.fetch(:version)&.to_s
          ).updated_requirements
        end

        private

        def git_commit_checker
          @git_commit_checker ||=
            GitCommitChecker.new(
              dependency: dependency,
              github_access_token: github_access_token
            )
        end

        def git_dependency?
          git_commit_checker.git_dependency?
        end

        def should_switch_source_from_git_to_rubygems?
          return false unless git_dependency?
          return false unless git_commit_checker.pinned?
          git_commit_checker.commit_in_released_version?(
            latest_resolvable_version_details.fetch(:version)
          )
        end

        def latest_version_details
          @latest_version_details ||= fetch_latest_version_details
        end

        def latest_resolvable_version_details
          @latest_resolvable_version_details ||=
            fetch_latest_resolvable_version_details
        end

        def fetch_latest_version_details
          dependency_source_type =
            dependency.requirements.map { |r| r.fetch(:source) }.
            uniq.compact.first&.fetch(:type)

          case dependency_source_type
          when nil then latest_rubygems_version_details
          when "rubygems" then latest_private_version_details
          when "git" then latest_git_version_details
          end
        end

        def fetch_latest_resolvable_version_details
          return latest_version_details unless gemfile

          in_a_temporary_bundler_context do
            definition = ::Bundler::Definition.build(
              "Gemfile",
              lockfile&.name,
              gems: [dependency.name]
            )

            if dependency_source.instance_of?(::Bundler::Source::Git)
              begin
                definition.resolve_remotely!
                dep = definition.resolve.find { |d| d.name == dependency.name }
                { version: dep.version, commit_sha: dep.source.revision }
              rescue ::Bundler::VersionConflict
                # Version conflict is likely due to the dependency update,
                # rather than an underlying issue with the Gemfile/Gemfile.lock.
                # Suppress the error and skip the update.
                { version: nil, commit_sha: nil }
              end
            else
              definition.resolve_remotely!
              dep = definition.resolve.find { |d| d.name == dependency.name }
              { version: dep.version }
            end
          end
        end

        def dependency_source
          return nil unless gemfile

          @dependency_source ||=
            in_a_temporary_bundler_context do
              ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
                find { |dep| dep.name == dependency.name }&.source
            end
        end

        def latest_rubygems_version_details
          latest_info = Gems.info(dependency.name)

          return nil if latest_info["version"].nil?

          # Rubygems excludes pre-releases from the `Gems.info` response,
          # so no need to filter them out.
          {
            version: Gem::Version.new(latest_info["version"]),
            sha: latest_info["sha"]
          }
        rescue JSON::ParserError
          nil
        end

        def latest_private_version_details
          spec =
            dependency_source.
            fetchers.flat_map do |fetcher|
              fetcher.
                specs_with_retry([dependency.name], dependency_source).
                search_all(dependency.name).
                reject { |s| s.version.prerelease? }
            end.
            sort_by(&:version).last
          { version: spec.version }
        rescue ::Bundler::Fetcher::AuthenticationRequiredError => error
          regex = /bundle config (?<repo>.*) username:password/
          source = error.message.match(regex)[:repo]
          raise Dependabot::PrivateSourceNotReachable, source
        end

        def latest_git_version_details
          dependency_source_details =
            dependency.requirements.map { |r| r.fetch(:source) }.
            uniq.compact.first

          SharedHelpers.in_a_forked_process do
            # Set auth details for GitHub
            ::Bundler.settings.set_command_option(
              "github.com",
              "x-access-token:#{github_access_token}"
            )

            # Note: we don't set the `ref`, as we want to unpin the dependency
            source = ::Bundler::Source::Git.new(
              "uri" => dependency_source_details[:url],
              "branch" => dependency_source_details[:branch],
              "name" => dependency.name
            )

            # Tell Bundler we're fine with fetching the source remotely
            source.instance_variable_set(:@allow_remote, true)

            spec = source.specs.first
            { version: spec.version, commit_sha: spec.source.revision }
          end
        rescue SharedHelpers::ChildProcessFailed => error
          handle_bundler_errors(error)
        end

        #########################
        # Bundler context setup #
        #########################

        # All methods below this line are used solely to set the Bundler
        # context. In future, they are a strong candidate to be refactored out
        # into a helper class.

        def in_a_temporary_bundler_context(error_handling: true)
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              # Remove installed gems from the default Rubygems index
              ::Gem::Specification.all = []

              # Set auth details for GitHub
              ::Bundler.settings.set_command_option(
                "github.com",
                "x-access-token:#{github_access_token}"
              )

              yield
            end
          end
        rescue SharedHelpers::ChildProcessFailed => error
          raise unless error_handling

          # Raise more descriptive errors
          handle_bundler_errors(error)
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/AbcSize
        def handle_bundler_errors(error)
          msg = error.error_class + " with message: " + error.error_message

          case error.error_class
          when "Bundler::Dsl::DSLError"
            # We couldn't evaluate the Gemfile, let alone resolve it
            raise Dependabot::DependencyFileNotEvaluatable, msg
          when "Bundler::Source::Git::MissingGitRevisionError"
            raise GitDependencyReferenceNotFound, dependency.name
          when "Bundler::Source::Git::GitCommandError"
            if error.error_message.match?(GIT_REF_REGEX)
              # We couldn't find the specified branch / commit (or the two
              # weren't compatible).
              gem_name =
                error.error_message.match(GIT_REF_REGEX).named_captures["path"].
                split("/").last.split("-")[0..-2].join
              raise GitDependencyReferenceNotFound, gem_name
            end

            bad_uris = inaccessible_git_dependencies.map { |s| s.source.uri }
            raise unless bad_uris.any?

            # We don't have access to one of repos required
            raise Dependabot::GitDependenciesNotReachable, bad_uris
          when "Bundler::GemNotFound", "Gem::InvalidSpecificationException",
               "Bundler::VersionConflict"
            # Bundler threw an error during resolution. Any of:
            # - the gem doesn't exist in any of the specified sources
            # - the gem wasn't specified properly
            # - the gem was specified at an incompatible version
            raise Dependabot::DependencyFileNotResolvable, msg
          when "RuntimeError"
            raise unless error.error_message.include?("Unable to find a spec")
            raise DependencyFileNotResolvable, msg
          else raise
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/AbcSize

        def inaccessible_git_dependencies
          in_a_temporary_bundler_context(error_handling: false) do
            ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
              reject do |spec|
                next true unless spec.source.is_a?(::Bundler::Source::Git)

                # Piggy-back off some private Bundler methods to configure the
                # URI with auth details in the same way Bundler does.
                git_proxy = spec.source.send(:git_proxy)
                uri = git_proxy.send(:configured_uri_for, spec.source.uri)
                uri += ".git" unless uri.end_with?(".git")
                uri += "/info/refs?service=git-upload-pack"
                Excon.get(uri, middlewares: SharedHelpers.excon_middleware).
                  status == 200
              end
          end
        end

        def gemfile
          prepared_dependency_files.find { |f| f.name == "Gemfile" }
        end

        def lockfile
          prepared_dependency_files.find { |f| f.name == "Gemfile.lock" }
        end

        def prepared_dependency_files
          @prepared_dependency_files ||=
            FilePreparer.new(
              dependency: dependency,
              dependency_files: dependency_files,
              remove_git_source: git_dependency? && git_commit_checker.pinned?
            ).prepared_dependency_files
        end

        def write_temporary_dependency_files
          prepared_dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end
      end
    end
  end
end

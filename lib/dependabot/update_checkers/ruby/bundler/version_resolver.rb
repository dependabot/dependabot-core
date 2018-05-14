# frozen_string_literal: true

require "bundler_definition_ruby_version_patch"
require "bundler_definition_bundler_version_patch"
require "bundler_git_source_patch"

require "excon"

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/utils/ruby/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class VersionResolver
          RUBYGEMS_API = "https://rubygems.org/api/v1/"
          GIT_REGEX = /git reset --hard [^\s]*` in directory (?<path>[^\s]*)/
          GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/
          PATH_REGEX = /The path `(?<path>.*)` does not exist/

          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def latest_version_details
            @latest_version_details ||= fetch_latest_version_details
          end

          def latest_resolvable_version_details
            @latest_resolvable_version_details ||=
              fetch_latest_resolvable_version_details
          end

          private

          attr_reader :dependency, :dependency_files, :credentials

          def fetch_latest_version_details
            case dependency_source
            when NilClass then latest_rubygems_version_details
            when ::Bundler::Source::Rubygems then latest_private_version_details
            when ::Bundler::Source::Git then latest_git_version_details
            end
          end

          def latest_rubygems_version_details
            return latest_rubygems_version_details_with_pre if wants_prerelease?

            # Rubygems excludes pre-releases from the `Gems.info` response,
            # so no need to filter them out.
            response = Excon.get(
              "https://rubygems.org/api/v1/gems/#{dependency.name}.json",
              idempotent: true,
              omit_default_port: true,
              middlewares: SharedHelpers.excon_middleware
            )

            latest_info = JSON.parse(response.body)
            return nil if latest_info["version"].nil?

            {
              version: Gem::Version.new(latest_info["version"]),
              sha: latest_info["sha"]
            }
          rescue JSON::ParserError
            nil
          end

          def latest_rubygems_version_details_with_pre
            response = Excon.get(
              RUBYGEMS_API + "versions/#{dependency.name}.json",
              idempotent: true,
              omit_default_port: true,
              middlewares: SharedHelpers.excon_middleware
            )

            latest_info = JSON.parse(response.body).
                          max_by { |d| Gem::Version.new(d["number"]) }

            {
              version: Gem::Version.new(latest_info["number"]),
              sha: latest_info["sha"]
            }
          rescue JSON::ParserError
            nil
          end

          def latest_private_version_details
            in_a_temporary_bundler_context do
              spec =
                dependency_source.
                fetchers.flat_map do |fetcher|
                  fetcher.
                    specs_with_retry([dependency.name], dependency_source).
                    search_all(dependency.name).
                    reject { |s| s.version.prerelease? && !wants_prerelease? }
                end.
                max_by(&:version)
              spec.nil? ? nil : { version: spec.version }
            end
          end

          def latest_git_version_details
            dependency_source_details =
              dependency.requirements.map { |r| r.fetch(:source) }.
              uniq.compact.first

            SharedHelpers.in_a_forked_process do
              # Set auth details
              relevant_credentials.each do |cred|
                ::Bundler.settings.set_command_option(
                  cred["host"],
                  cred["token"] || "#{cred['username']}:#{cred['password']}"
                )
              end

              # Note: we don't set the `ref`, as we want to unpin the dependency
              source = ::Bundler::Source::Git.new(
                "uri" => dependency_source_details[:url],
                "branch" => dependency_source_details[:branch],
                "name" => dependency.name,
                "submodules" => true
              )

              # Tell Bundler we're fine with fetching the source remotely
              source.instance_variable_set(:@allow_remote, true)

              spec = source.specs.first
              { version: spec.version, commit_sha: spec.source.revision }
            end
          rescue SharedHelpers::ChildProcessFailed => error
            handle_bundler_errors(error)
          end

          def wants_prerelease?
            current_version = dependency.version
            if current_version && Gem::Version.correct?(current_version) &&
               Gem::Version.new(current_version).prerelease?
              return true
            end

            dependency.requirements.any? do |req|
              req[:requirement].match?(/[a-z]/i)
            end
          end

          def fetch_latest_resolvable_version_details
            return latest_version_details unless gemfile

            in_a_temporary_bundler_context do
              dep = dependency_from_definition

              # If the dependency wasn't found in the definition, it's because
              # the Gemfile didn't import the gemspec. This is unusual, but
              # the correct behaviour if/when it happens is to behave as if
              # the repo was gemspec-only
              next latest_version_details unless dep

              # If the old Gemfile index was used then it won't have checked
              # Ruby compatibility. Fix that by doing the check manually (and
              # saying no update is possible if the Ruby version is a mismatch)
              next nil if ruby_version_incompatible?(dep)

              details = { version: dep.version }
              if dep.source.instance_of?(::Bundler::Source::Git)
                details[:commit_sha] = dep.source.revision
              end
              details
            end
          end

          def dependency_from_definition
            dependencies_to_unlock = [dependency.name]
            begin
              definition = build_definition(dependencies_to_unlock)
              definition.resolve_remotely!
            rescue ::Bundler::GemNotFound => error
              # Handle yanked dependencies
              raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)
              gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                         named_captures["name"]
              raise if dependencies_to_unlock.include?(gem_name)
              dependencies_to_unlock << gem_name
              retry
            rescue ::Bundler::HTTPError => error
              # Retry network errors
              attempt ||= 1
              attempt += 1
              raise if attempt > 3 || !error.message.include?("Network error")
              retry
            end

            definition.resolve.find { |d| d.name == dependency.name }
          end

          def ruby_version_incompatible?(dep)
            return false unless dep.source.is_a?(::Bundler::Source::Rubygems)
            fetcher = dep.source.fetchers.first.fetchers.first

            # It's only the old index we have a problem with
            return false unless fetcher.is_a?(::Bundler::Fetcher::Dependency)

            # If no Ruby version is specified, we don't have a problem
            return false unless ruby_version

            versions = Excon.get(
              "https://rubygems.org/api/v1/versions/#{dependency.name}.json",
              idempotent: true,
              omit_default_port: true,
              middlewares: SharedHelpers.excon_middleware
            )

            ruby_requirement =
              JSON.parse(versions.body).
              find { |details| details["number"] == dep.version.to_s }&.
              fetch("ruby_version", nil)

            # Give the benefit of the doubt if we can't find the version's
            # required Ruby version.
            return false unless ruby_requirement
            ruby_requirement = Utils::Ruby::Requirement.new(ruby_requirement)

            !ruby_requirement.satisfied_by?(ruby_version)
          rescue JSON::ParserError
            # Give the benefit of the doubt if something goes wrong fetching
            # version details (could be that it's a private index, etc.)
            false
          end

          def build_definition(dependencies_to_unlock)
            ::Bundler::Definition.build(
              "Gemfile", lockfile&.name, gems: dependencies_to_unlock
            )
          end

          def dependency_source
            return nil unless gemfile

            @dependency_source ||=
              in_a_temporary_bundler_context do
                ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
                  find { |dep| dep.name == dependency.name }&.source
              end
          end

          def ruby_version
            return nil unless gemfile

            @ruby_version ||= build_definition([]).ruby_version&.gem_version
          end

          #########################
          # Bundler context setup #
          #########################

          def in_a_temporary_bundler_context(error_handling: true)
            base_directory = dependency_files.first.directory
            SharedHelpers.in_a_temporary_directory(base_directory) do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details
                relevant_credentials.each do |cred|
                  ::Bundler.settings.set_command_option(
                    cred["host"],
                    cred["token"] || "#{cred['username']}:#{cred['password']}"
                  )
                end

                yield
              end
            end
          rescue SharedHelpers::ChildProcessFailed => error
            raise unless error_handling

            # Raise more descriptive errors
            handle_bundler_errors(error)
          end

          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/MethodLength
          def handle_bundler_errors(error)
            path_regex =
              Regexp.escape(SharedHelpers::BUMP_TMP_DIR_PATH) + "\/" +
              Regexp.escape(SharedHelpers::BUMP_TMP_FILE_PREFIX) + "[^/]*"
            msg =
              error.error_class + " with message: " +
              error.error_message.gsub(/#{path_regex}/, "/dependabot_tmp_dir")

            case error.error_class
            when "Bundler::Dsl::DSLError"
              # We couldn't evaluate the Gemfile, let alone resolve it
              raise Dependabot::DependencyFileNotEvaluatable, msg
            when "Bundler::Source::Git::MissingGitRevisionError"
              raise GitDependencyReferenceNotFound, dependency.name
            when "Bundler::PathError"
              gem_name =
                error.error_message.match(PATH_REGEX).
                named_captures["path"].
                split("/").last.split("-")[0..-2].join
              raise Dependabot::PathDependenciesNotReachable, [gem_name]
            when "Bundler::Source::Git::GitCommandError"
              if error.error_message.match?(GIT_REGEX)
                # We couldn't find the specified branch / commit (or the two
                # weren't compatible).
                gem_name =
                  error.error_message.match(GIT_REGEX).
                  named_captures["path"].
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
            when "Bundler::Fetcher::AuthenticationRequiredError"
              regex = /bundle config (?<source>.*) username:password/
              source = error.error_message.match(regex)[:source]
              raise Dependabot::PrivateSourceNotReachable, source
            when "Bundler::Fetcher::BadAuthenticationError"
              regex = /Bad username or password for (?<source>.*)\.$/
              source = error.error_message.match(regex)[:source]
              raise Dependabot::PrivateSourceNotReachable, source
            when "Bundler::Fetcher::CertificateFailureError"
              regex = /verify the SSL certificate for (?<source>.*)\.$/
              source = error.error_message.match(regex)[:source]
              raise Dependabot::PrivateSourceCertificateFailure, source
            when "Bundler::HTTPError"
              regex = /Could not fetch specs from (?<source>.*)$/
              raise unless error.error_message.match?(regex)
              source = error.error_message.match(regex)[:source]
              raise if source.include?("rubygems")
              raise Dependabot::PrivateSourceNotReachable, source
            else raise
            end
          end
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/MethodLength

          def inaccessible_git_dependencies
            in_a_temporary_bundler_context(error_handling: false) do
              ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
                reject do |spec|
                  next true unless spec.source.is_a?(::Bundler::Source::Git)

                  # Piggy-back off some private Bundler methods to configure the
                  # URI with auth details in the same way Bundler does.
                  git_proxy = spec.source.send(:git_proxy)
                  uri = spec.source.uri.gsub("git://", "https://")
                  uri = git_proxy.send(:configured_uri_for, uri)
                  uri += ".git" unless uri.end_with?(".git")
                  uri += "/info/refs?service=git-upload-pack"

                  begin
                    Excon.get(
                      uri,
                      idempotent: true,
                      omit_default_port: true,
                      middlewares: SharedHelpers.excon_middleware
                    ).status == 200
                  rescue Excon::Error::Socket, Excon::Error::Timeout
                    false
                  end
                end
            end
          end

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
          end

          def relevant_credentials
            credentials.select do |cred|
              next true if cred["type"] == "git_source"
              next true if cred["type"] == "rubygems_server"
              false
            end
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength

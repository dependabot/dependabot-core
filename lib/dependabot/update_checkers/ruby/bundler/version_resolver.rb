# frozen_string_literal: true

require "bundler_definition_version_patch"
require "bundler_git_source_patch"

require "excon"

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class VersionResolver
          GIT_REF_REGEX =
            /git reset --hard [^\s]*` in directory (?<path>[^\s]*)/

          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def latest_version_details
            @latest_version_details ||=
              fetch_latest_version_details
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
            response =
              Excon.get(
                "https://rubygems.org/api/v1/gems/#{dependency.name}.json",
                idempotent: true,
                middlewares: SharedHelpers.excon_middleware
              )

            latest_info = JSON.parse(response.body)

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
            in_a_temporary_bundler_context do
              spec =
                dependency_source.
                fetchers.flat_map do |fetcher|
                  fetcher.
                    specs_with_retry([dependency.name], dependency_source).
                    search_all(dependency.name).
                    reject { |s| s.version.prerelease? }
                end.
                sort_by(&:version).last
              return nil if spec.nil?
              { version: spec.version }
            end
          end

          def latest_git_version_details
            dependency_source_details =
              dependency.requirements.map { |r| r.fetch(:source) }.
              uniq.compact.first

            SharedHelpers.in_a_forked_process do
              # Set auth details
              credentials.each do |cred|
                ::Bundler.settings.set_command_option(
                  cred["host"],
                  cred["token"] || "#{cred['username']}:#{cred['password']}"
                )
              end

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

          def fetch_latest_resolvable_version_details
            return latest_version_details unless gemfile

            in_a_temporary_bundler_context do
              definition = ::Bundler::Definition.build(
                "Gemfile",
                lockfile&.name,
                gems: [dependency.name]
              )

              definition.resolve_remotely!
              dep = definition.resolve.find { |d| d.name == dependency.name }

              # If the dependency wasn't found in the definition, it's because
              # the Gemfile didn't import the gemspec. This is unusual, but
              # the correct behaviour if/when it happens is to behave as if
              # the repo was gemspec-only
              next latest_version_details unless dep

              details = { version: dep.version }
              if dependency_source.instance_of?(::Bundler::Source::Git)
                details[:commit_sha] = dep.source.revision
              end
              details
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

          #########################
          # Bundler context setup #
          #########################

          def in_a_temporary_bundler_context(error_handling: true)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details
                credentials.each do |cred|
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
                  error.error_message.match(GIT_REF_REGEX).
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

                  Excon.get(
                    uri,
                    idempotent: true,
                    middlewares: SharedHelpers.excon_middleware
                  ).status == 200
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
        end
      end
    end
  end
end

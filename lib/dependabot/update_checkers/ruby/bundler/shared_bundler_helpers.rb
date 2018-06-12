# frozen_string_literal: true

require "bundler_definition_ruby_version_patch"
require "bundler_definition_bundler_version_patch"
require "bundler_git_source_patch"

require "excon"

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        module SharedBundlerHelpers
          GIT_REGEX = /git reset --hard [^\s]*` in directory (?<path>[^\s]*)/
          GIT_REF_REGEX = /does not exist in the repository (?<path>[^\s]*)\./
          PATH_REGEX = /The path `(?<path>.*)` does not exist/
          RETRYABLE_PRIVATE_REGISTRY_ERRORS = %w(
            Bundler::GemNotFound
            Gem::InvalidSpecificationException
            Bundler::VersionConflict
            Bundler::HTTPError
          ).freeze

          attr_reader :dependency_files, :credentials

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
                    cred.fetch("host"),
                    cred["token"] || "#{cred['username']}:#{cred['password']}"
                  )
                end

                yield
              end
            end
          rescue SharedHelpers::ChildProcessFailed => error
            if RETRYABLE_PRIVATE_REGISTRY_ERRORS.include?(error.error_class) &&
               private_registry_credentials.any? && !@retrying
              @retrying = true
              sleep(rand(1.0..5.0))
              retry
            end

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
              error.error_message.gsub(/#{path_regex}/, "dependabot_tmp_dir")

            case error.error_class
            when "Bundler::Dsl::DSLError", "Bundler::GemspecError"
              # We couldn't evaluate the Gemfile, let alone resolve it
              raise Dependabot::DependencyFileNotEvaluatable, msg
            when "Bundler::Source::Git::MissingGitRevisionError"
              gem_name =
                error.error_message.match(GIT_REF_REGEX).
                named_captures["path"].
                split("/").last
              raise GitDependencyReferenceNotFound, gem_name
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
            when "Bundler::Fetcher::AuthenticationRequiredError"
              regex = /bundle config (?<source>.*) username:password/
              source = error.error_message.match(regex)[:source]
              raise Dependabot::PrivateSourceAuthenticationFailure, source
            when "Bundler::Fetcher::BadAuthenticationError"
              regex = /Bad username or password for (?<source>.*)\.$/
              source = error.error_message.match(regex)[:source]
              raise Dependabot::PrivateSourceAuthenticationFailure, source
            when "Bundler::Fetcher::CertificateFailureError"
              regex = /verify the SSL certificate for (?<source>.*)\.$/
              source = error.error_message.match(regex)[:source]
              raise Dependabot::PrivateSourceCertificateFailure, source
            when "Bundler::HTTPError"
              regex = /Could not fetch specs from (?<source>.*)$/
              raise unless error.error_message.match?(regex)
              source = error.error_message.match(regex)[:source]
              raise if source.include?("rubygems")
              raise Dependabot::PrivateSourceAuthenticationFailure, source
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
                      **SharedHelpers.excon_defaults
                    ).status == 200
                  rescue Excon::Error::Socket, Excon::Error::Timeout
                    false
                  end
                end
            end
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
          end

          def relevant_credentials
            private_registry_credentials + git_source_credentials
          end

          def private_registry_credentials
            credentials.select { |cred| cred["type"] == "rubygems_server" }
          end

          def git_source_credentials
            credentials.select { |cred| cred["type"] == "git_source" }
          end
        end
      end
    end
  end
end

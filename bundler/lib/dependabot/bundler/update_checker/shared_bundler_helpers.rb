# frozen_string_literal: true

require "dependabot/monkey_patches/bundler/definition_ruby_version_patch"
require "dependabot/monkey_patches/bundler/definition_bundler_version_patch"
require "dependabot/monkey_patches/bundler/git_source_patch"

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class UpdateChecker
      module SharedBundlerHelpers
        GIT_REGEX = /reset --hard [^\s]*` in directory (?<path>[^\s]*)/.freeze
        GIT_REF_REGEX = /not exist in the repository (?<path>[^\s]*)\./.freeze
        PATH_REGEX = /The path `(?<path>.*)` does not exist/.freeze
        RETRYABLE_ERRORS = %w(
          Bundler::HTTPError
          Bundler::Fetcher::FallbackError
        ).freeze
        RETRYABLE_PRIVATE_REGISTRY_ERRORS = %w(
          Bundler::GemNotFound
          Gem::InvalidSpecificationException
          Bundler::VersionConflict
          Bundler::HTTPError
          Bundler::Fetcher::FallbackError
        ).freeze

        attr_reader :dependency_files, :credentials

        #########################
        # Bundler context setup #
        #########################

        def in_a_temporary_bundler_context(error_handling: true)
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do |tmp_dir|
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              # Set the path for path gemspec correctly
              ::Bundler.instance_variable_set(:@root, tmp_dir)

              # Remove installed gems from the default Rubygems index
              ::Gem::Specification.all = []

              # Set auth details
              relevant_credentials.each do |cred|
                token = cred["token"] ||
                        "#{cred['username']}:#{cred['password']}"

                ::Bundler.settings.set_command_option(
                  cred.fetch("host"),
                  token.gsub("@", "%40F").gsub("?", "%3F")
                )
              end

              yield
            end
          end
        rescue SharedHelpers::ChildProcessFailed, ArgumentError => error
          retry_count ||= 0
          retry_count += 1
          if retryable_error?(error) && retry_count <= 2
            sleep(rand(1.0..5.0)) && retry
          end

          raise unless error_handling

          # Raise more descriptive errors
          handle_bundler_errors(error)
        end

        def retryable_error?(error)
          return true if error.message == "marshal data too short"
          return false if error.is_a?(ArgumentError)
          return true if RETRYABLE_ERRORS.include?(error.error_class)

          unless RETRYABLE_PRIVATE_REGISTRY_ERRORS.include?(error.error_class)
            return false
          end

          private_registry_credentials.any?
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def handle_bundler_errors(error)
          if error.message == "marshal data too short"
            msg = "Error evaluating your dependency files: #{error.message}"
            raise Dependabot::DependencyFileNotEvaluatable, msg
          end
          raise if error.is_a?(ArgumentError)

          msg = error.error_class + " with message: " + error.error_message

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
               "Bundler::VersionConflict", "Bundler::CyclicDependencyError"
            # Bundler threw an error during resolution. Any of:
            # - the gem doesn't exist in any of the specified sources
            # - the gem wasn't specified properly
            # - the gem was specified at an incompatible version
            raise Dependabot::DependencyFileNotResolvable, msg
          when "Bundler::Fetcher::AuthenticationRequiredError"
            regex = /bundle config (?<source>.*) username:password/
            source = error.error_message.match(regex)[:source]
            source = "https://" + source unless source.match?(%r{^https?://})
            raise Dependabot::PrivateSourceAuthenticationFailure, source
          when "Bundler::Fetcher::BadAuthenticationError"
            regex = /Bad username or password for (?<source>.*)\.$/
            source = error.error_message.match(regex)[:source]
            source = "https://" + source unless source.match?(%r{^https?://})
            raise Dependabot::PrivateSourceAuthenticationFailure, source
          when "Bundler::Fetcher::CertificateFailureError"
            regex = /verify the SSL certificate for (?<source>.*)\.$/
            source = error.error_message.match(regex)[:source]
            source = "https://" + source unless source.match?(%r{^https?://})
            raise Dependabot::PrivateSourceCertificateFailure, source
          when "Bundler::HTTPError"
            regex = /Could not fetch specs from (?<source>.*)$/
            if error.error_message.match?(regex)
              source = error.error_message.match(regex)[:source]
              source = "https://" + source unless source.match?(%r{^https?://})
              raise if source.include?("rubygems.org")

              raise Dependabot::PrivateSourceTimedOut, source
            end

            # JFrog can serve a 403 if the credentials provided are good but
            # don't have access to a particular gem.
            raise unless error.error_message.include?("permitted to deploy")
            raise unless jfrog_source

            raise Dependabot::PrivateSourceAuthenticationFailure, jfrog_source
          else raise
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        def inaccessible_git_dependencies
          in_a_temporary_bundler_context(error_handling: false) do
            ::Bundler::Definition.build(gemfile.name, nil, {}).dependencies.
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

        def jfrog_source
          source =
            in_a_temporary_bundler_context(error_handling: false) do
              ::Bundler::Definition.build(gemfile.name, nil, {}).
                send(:sources).
                rubygems_remotes.
                find { |uri| uri.host.include?("jfrog") }&.
                host
            end
          return unless source

          source = "https://" + source unless source.match?(%r{^https?://})
          source
        end

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          File.write(lockfile.name, sanitized_lockfile_body) if lockfile
        end

        def relevant_credentials
          [
            *git_source_credentials,
            *private_registry_credentials
          ].select { |cred| cred["password"] || cred["token"] }
        end

        def private_registry_credentials
          credentials.
            select { |cred| cred["type"] == "rubygems_server" }
        end

        def git_source_credentials
          credentials.
            select { |cred| cred["password"] || cred["token"] }.
            select { |cred| cred["type"] == "git_source" }
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        def sanitized_lockfile_body
          re = FileUpdater::LockfileUpdater::LOCKFILE_ENDING
          lockfile.content.gsub(re, "")
        end
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "uri"

require "dependabot/bundler/update_checker"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Bundler
    class UpdateChecker
      module SharedBundlerHelpers
        include Kernel

        extend T::Sig
        extend T::Helpers

        abstract!

        sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
        def options; end

        sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
        def dependency_files; end

        sig { abstract.returns(T.nilable(String)) }
        def repo_contents_path; end

        sig { abstract.returns(T::Array[Dependabot::Credential]) }
        def credentials; end

        GIT_REGEX = /reset --hard [^\s]*` in directory (?<path>[^\s]*)/
        GIT_REF_REGEX = /not exist in the repository (?<path>[^\s]*)\./
        PATH_REGEX = /The path `(?<path>.*)` does not exist/

        module BundlerErrorPatterns
          MISSING_AUTH_REGEX = /bundle config set --global (?<source>.*) username:password/

          BAD_AUTH_REGEX = /Bad username or password for (?<source>.*)\.$/
          FORBIDDEN_AUTH_REGEX = /Access token could not be authenticated for (?<source>.*)\.$/
          BAD_CERT_REGEX = /verify the SSL certificate for (?<source>.*)\.$/
          HTTP_ERR_REGEX = /Could not fetch specs from (?<source>\S+)/
        end

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

        #########################
        # Bundler context setup #
        #########################

        sig do
          params(
            error_handling: T::Boolean,
            _blk: T.proc.params(arg0: String).returns(T.untyped)
          )
            .returns(T.untyped)
        end
        def in_a_native_bundler_context(error_handling: true, &_blk)
          SharedHelpers
            .in_a_temporary_repo_directory(base_directory,
                                           repo_contents_path) do |tmp_dir|
            write_temporary_dependency_files

            yield(tmp_dir.to_s)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          retry_count ||= 0
          retry_count += 1
          sleep(rand(1.0..5.0)) && retry if retryable_error?(e) && retry_count <= 2

          error_handling ? handle_bundler_errors(e) : raise
        end

        sig { returns(String) }
        def base_directory
          T.must(dependency_files.first).directory
        end

        sig { params(error: Dependabot::SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
        def retryable_error?(error)
          return true if error.error_class == "JSON::ParserError"
          return true if RETRYABLE_ERRORS.include?(error.error_class)

          return false unless RETRYABLE_PRIVATE_REGISTRY_ERRORS.include?(error.error_class)

          private_registry_credentials.any?
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        sig { params(error: Dependabot::SharedHelpers::HelperSubprocessFailed).void }
        def handle_bundler_errors(error)
          if error.error_class == "JSON::ParserError"
            msg = "Error evaluating your dependency files: #{error.message}"
            raise Dependabot::DependencyFileNotEvaluatable, msg
          end

          msg = error.error_class + " with message: " + error.message

          case error.error_class
          when "Bundler::Dsl::DSLError", "Bundler::GemspecError"
            # We couldn't evaluate the Gemfile, let alone resolve it
            raise Dependabot::DependencyFileNotEvaluatable, msg
          when "Bundler::Source::Git::MissingGitRevisionError"
            match_data = error.message.match(GIT_REF_REGEX)
            gem_name = T.must(T.must(match_data).named_captures["path"])
                        .split("/").last
            raise GitDependencyReferenceNotFound, T.must(gem_name)
          when "Bundler::PathError"
            match_data = error.message.match(PATH_REGEX)
            path = T.must(T.must(match_data).named_captures["path"])
            gem_name = T.must(T.must(path.split("/").last).split("-")[0..-2]).join
            raise Dependabot::PathDependenciesNotReachable, [gem_name]
          when "Bundler::Source::Git::GitCommandError"
            if error.message.match?(GIT_REGEX)
              # We couldn't find the specified branch / commit (or the two
              # weren't compatible).
              match_data = error.message.match(GIT_REGEX)
              path = T.must(T.must(match_data).named_captures["path"])
              gem_name = T.must(T.must(path.split("/").last).split("-")[0..-2]).join
              raise GitDependencyReferenceNotFound, gem_name
            end

            bad_uris = inaccessible_git_dependencies.map do |spec|
              spec.fetch("uri")
            end
            raise unless bad_uris.any?

            # We don't have access to one of repos required
            raise Dependabot::GitDependenciesNotReachable, bad_uris.uniq
          when "Bundler::GemNotFound", "Gem::InvalidSpecificationException",
               "Bundler::VersionConflict", "Bundler::CyclicDependencyError",
               "Bundler::SolveFailure"
            # Bundler threw an error during resolution. Any of:
            # - the gem doesn't exist in any of the specified sources
            # - the gem wasn't specified properly
            # - the gem was specified at an incompatible version
            raise Dependabot::DependencyFileNotResolvable, msg
          when "Bundler::Fetcher::AuthenticationRequiredError"
            regex = BundlerErrorPatterns::MISSING_AUTH_REGEX
            source = T.must(T.must(error.message.match(regex))[:source])
            raise Dependabot::PrivateSourceAuthenticationFailure, source
          when "Bundler::Fetcher::AuthenticationForbiddenError"
            regex = BundlerErrorPatterns::FORBIDDEN_AUTH_REGEX
            source = T.must(T.must(error.message.match(regex))[:source])
            raise Dependabot::PrivateSourceAuthenticationFailure, source
          when "Bundler::Fetcher::BadAuthenticationError"
            regex = BundlerErrorPatterns::BAD_AUTH_REGEX
            source = T.must(T.must(error.message.match(regex))[:source])
            raise Dependabot::PrivateSourceAuthenticationFailure, source
          when "Bundler::Fetcher::CertificateFailureError"
            regex = BundlerErrorPatterns::BAD_CERT_REGEX
            source = T.must(T.must(error.message.match(regex))[:source])
            raise Dependabot::PrivateSourceCertificateFailure, source
          when "Bundler::HTTPError"
            regex = BundlerErrorPatterns::HTTP_ERR_REGEX
            if error.message.match?(regex)
              source = T.must(T.must(error.message.match(regex))[:source])
              raise if [
                "rubygems.org",
                "www.rubygems.org"
              ].include?(URI(source).host)

              raise Dependabot::PrivateSourceTimedOut, source
            end

            # JFrog can serve a 403 if the credentials provided are good but
            # don't have access to a particular gem.
            raise unless error.message.include?("permitted to deploy")
            raise unless jfrog_source

            raise Dependabot::PrivateSourceAuthenticationFailure, jfrog_source
          else raise
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def inaccessible_git_dependencies
          in_a_native_bundler_context(error_handling: false) do |tmp_dir|
            git_specs = NativeHelpers.run_bundler_subprocess(
              bundler_version: bundler_version,
              function: "git_specs",
              options: options,
              args: {
                dir: tmp_dir,
                gemfile_name: T.must(gemfile).name,
                credentials: credentials
              }
            )
            git_specs.reject do |spec|
              uri = URI.parse(spec.fetch("auth_uri"))
              next false unless uri.scheme&.match?(/https?/o)

              Dependabot::RegistryClient.get(
                url: uri.to_s,
                headers: { "Accept-Encoding" => "gzip" }
              ).status == 200
            rescue Excon::Error::Socket, Excon::Error::Timeout
              false
            end
          end
        end

        sig { returns(T.nilable(String)) }
        def jfrog_source
          @jfrog_source = T.let(@jfrog_source, T.nilable(String)) if @jfrog_source.nil?
          return @jfrog_source unless @jfrog_source.nil?

          @jfrog_source = in_a_native_bundler_context(error_handling: false) do |dir|
            NativeHelpers.run_bundler_subprocess(
              bundler_version: bundler_version,
              function: "jfrog_source",
              options: options,
              args: {
                dir: dir,
                gemfile_name: T.must(gemfile).name,
                credentials: credentials
              }
            )
          end
        end

        sig { void }
        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          lockfile_obj = lockfile
          File.write(lockfile_obj.name, lockfile_obj.content) if lockfile_obj
        end

        sig { returns(T::Array[Dependabot::Credential]) }
        def private_registry_credentials
          credentials
            .select { |cred| cred["type"] == "rubygems_server" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" } ||
            dependency_files.find { |f| f.name == "gems.rb" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" } ||
            dependency_files.find { |f| f.name == "gems.locked" }
        end

        private

        sig { abstract.returns(String) }
        def bundler_version; end
      end
    end
  end
end

# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "tmpdir"

require "dependabot/hex/credential_helpers"
require "dependabot/hex/file_updater"
require "dependabot/hex/file_updater/mixfile_updater"
require "dependabot/hex/file_updater/mixfile_sanitizer"
require "dependabot/hex/file_updater/mixfile_requirement_updater"
require "dependabot/hex/native_helpers"
require "dependabot/hex/version"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    class FileUpdater
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @updated_lockfile_content = T.let(nil, T.nilable(String))
        end

        sig { returns(String) }
        def updated_lockfile_content
          unless @updated_lockfile_content
            result = Dir.mktmpdir("dependabot-hex-home") do |hex_home|
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files
                FileUtils.cp(elixir_helper_do_update_path, "do_update.exs")

                env = mix_env(hex_home)
                SharedHelpers.with_git_configured(credentials: credentials) do
                  CredentialHelpers.configure(credentials: credentials, env: env)
                  run_mix_command(
                    mix_run_command("do_update.exs", dependency.name),
                    fingerprint: "mix run do_update.exs <dependency_name>",
                    env: env
                  )
                  run_mix_command(
                    ["mix", "deps.get", "--no-archives-check"],
                    fingerprint: "mix deps.get",
                    env: env
                  )
                  File.read("mix.lock")
                end
              end
            end
            @updated_lockfile_content = result
          end

          post_process_lockfile(@updated_lockfile_content)
        rescue SharedHelpers::HelperSubprocessFailed => e
          sanitized_error = CredentialHelpers.sanitize_error(error: e, credentials: credentials)
          error = handle_hex_errors(sanitized_error)
          CredentialHelpers.raise_translated_error(original_error: e, error: error)
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(Dependabot::Dependency) }
        def dependency
          # For now, we'll only ever be updating a single dep for Elixir
          T.must(dependencies.first)
        end

        sig { params(content: String).returns(String) }
        def post_process_lockfile(content)
          lockfile_content = T.must(lockfile.content)
          return content unless lockfile_content.start_with?("%{\"")
          return content if content.start_with?("%{\"")

          # Substitute back old file beginning and ending
          content.sub(/\A%\{\n  "/, "%{\"").sub("},\n}", "}}")
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(StandardError) }
        def handle_hex_errors(error)
          source = CredentialHelpers.authentication_source(error.message)
          return Dependabot::PrivateSourceAuthenticationFailure.new(source) if source

          lines = error.message.lines.map(&:strip)
          if lines.include?("** (Mix) Hex dependency resolution failed")
            return Dependabot::DependencyFileNotResolvable.new("Hex dependency resolution failed")
          end

          input_error = lines.find do |line|
            line.match?(/\A(?:\*\* \(Mix\) )?Unknown package version .+ in lockfile\z/) ||
              line.match?(
                %r{
                  \A\*\*[ ]\(Mix\)[ ]Required[ ]version[ ].+[ ]for[ ]package[ ].+[ ]is[ ]incorrectly[ ]specified
                  [ ]\(from:[ ](?:[^/\r\n]+/)*mix\.exs\)\z
                }x
              )
          end
          return Dependabot::DependencyFileNotResolvable.new(input_error) if input_error

          error
        end

        sig do
          params(
            command: T::Array[String],
            fingerprint: String,
            env: T::Hash[String, String]
          ).void
        end
        def run_mix_command(command, fingerprint:, env:)
          SharedHelpers.run_shell_command(command, env: env, fingerprint: fingerprint)
        end

        sig { params(script: String, args: String).returns(T::Array[String]) }
        def mix_run_command(script, *args)
          [
            "mix", "run", "--no-deps-check", "--no-start", "--no-compile",
            "--no-elixir-version-check", script, "--", *args
          ]
        end

        sig { void }
        def write_temporary_dependency_files
          mixfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, mixfile_content_for_lockfile_generation(file))
          end

          File.write("mix.lock", T.must(lockfile.content))

          dependency_files.select(&:support_file).each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitize_mixfile(T.must(file.content)))
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def mixfile_content_for_lockfile_generation(file)
          content = updated_mixfile_content(file)
          content = lock_mixfile_dependency_versions(content, file.name)
          sanitize_mixfile(content)
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def updated_mixfile_content(file)
          MixfileUpdater.new(
            dependencies: dependencies,
            mixfile: file
          ).updated_mixfile_content
        end

        sig { params(mixfile_content: String, filename: String).returns(String) }
        def lock_mixfile_dependency_versions(mixfile_content, filename)
          dependencies
            .reduce(mixfile_content.dup) do |content, dep|
              # Run on the updated mixfile content, so we're updating from the
              # updated requirements
              req_details = dep.requirements.find { |r| r.file == filename }

              next content unless req_details
              next content unless Hex::Version.correct?(dep.version)

              MixfileRequirementUpdater.new(
                dependency_name: dep.name,
                mixfile_content: content,
                previous_requirement: req_details.requirement_string,
                updated_requirement: dep.version,
                insert_if_bare: true
              ).updated_content
            end
        end

        sig { params(content: String).returns(String) }
        def sanitize_mixfile(content)
          MixfileSanitizer.new(mixfile_content: content).sanitized_content
        end

        sig { params(hex_home: String).returns(T::Hash[String, String]) }
        def mix_env(hex_home)
          {
            "HEX_HOME" => hex_home,
            "MIX_EXS" => "mix.exs",
            "MIX_QUIET" => "1"
          }
        end

        sig { returns(String) }
        def elixir_helper_do_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/do_update.exs")
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def mixfiles
          dependency_files.select { |f| f.name.end_with?("mix.exs") }
        end

        sig { returns(Dependabot::DependencyFile) }
        def lockfile
          @lockfile ||= T.let(
            T.must(dependency_files.find { |f| f.name == "mix.lock" }),
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end

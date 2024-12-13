# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/hex/file_updater/mixfile_sanitizer"
require "dependabot/hex/native_helpers"
require "dependabot/hex/language"
require "dependabot/hex/package_manager"
require "dependabot/hex/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

# For docs, see https://hexdocs.pm/mix/Mix.Tasks.Deps.html
module Dependabot
  module Hex
    extend T::Sig
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig
      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        # TODO: git sourced dependency's mixfiles are evaluated. Provide guards before removing this.
        raise ::Dependabot::UnexpectedExternalCode if @reject_external_code

        dependency_set = DependencySet.new

        dependency_details.each do |dep|
          git_dependency = dep["source"]&.fetch("type") == "git"

          dependency_set <<
            Dependency.new(
              name: dep["name"],
              version: git_dependency ? dep["checksum"] : dep["version"],
              requirements: [{
                requirement: dep["requirement"],
                groups: dep["groups"],
                source: dep["source"] && symbolize_keys(dep["source"]),
                file: dep["from"]
              }],
              package_manager: "hex"
            )
        end

        dependency_set.dependencies.sort_by(&:name)
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(begin
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          )
        end, T.nilable(Dependabot::Ecosystem))
      end

      private

      sig { returns(T::Array[T.any(T::Hash[String, String], T::Hash[String, T.untyped])]) }
      def dependency_details
        SharedHelpers.in_a_temporary_directory do
          write_sanitized_mixfiles
          write_sanitized_supporting_files
          File.write("mix.lock", lockfile&.content) if lockfile
          FileUtils.cp(elixir_helper_parse_deps_path, "parse_deps.exs")

          SharedHelpers.run_helper_subprocess(
            env: mix_env,
            command: "mix run #{elixir_helper_path}",
            function: "parse",
            args: [Dir.pwd],
            stderr_to_stdout: true
          )
        end
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        result_json =
          e.message.lines
           .drop_while { |l| !l.start_with?('{"result":') }
           .join

        raise DependencyFileNotEvaluatable, e.message if result_json.empty?

        JSON.parse(result_json).fetch("result")
      end

      sig { void }
      def write_sanitized_mixfiles
        mixfiles.each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, sanitize_mixfile(T.must(file.content)))
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def write_sanitized_supporting_files
        dependency_files.select(&:support_file).each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, sanitize_mixfile(T.must(file.content)))
        end
      end

      sig { params(content: String).returns(String) }
      def sanitize_mixfile(content)
        Hex::FileUpdater::MixfileSanitizer.new(
          mixfile_content: content
        ).sanitized_content
      end

      sig { returns(T::Hash[String, String]) }
      def mix_env
        {
          "MIX_EXS" => File.join(NativeHelpers.hex_helpers_dir, "mix.exs"),
          "MIX_LOCK" => File.join(NativeHelpers.hex_helpers_dir, "mix.lock"),
          "MIX_DEPS" => File.join(NativeHelpers.hex_helpers_dir, "deps"),
          "MIX_QUIET" => "1"
        }
      end

      sig { returns(String) }
      def elixir_helper_path
        File.join(NativeHelpers.hex_helpers_dir, "lib/run.exs")
      end

      sig { returns(String) }
      def elixir_helper_parse_deps_path
        File.join(NativeHelpers.hex_helpers_dir, "lib/parse_deps.exs")
      end

      sig { override.void }
      def check_required_files
        raise "No mixfile!" if mixfiles.none?
      end

      sig { params(hash: T::Hash[String, String]).returns(T::Hash[Symbol, T.nilable(String)]) }
      def symbolize_keys(hash)
        hash.keys.to_h { |k| [k.to_sym, hash[k]] }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def mixfiles
        dependency_files.select { |f| f.name.end_with?("mix.exs") }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(get_original_file("mix.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(hex_version),
          T.nilable(Dependabot::Hex::PackageManager)
        )
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        @language ||= T.let(
          Language.new(elixir_version),
          T.nilable(Dependabot::Hex::Language)
        )
      end

      sig { returns(String) }
      def hex_version
        T.must(T.must(hex_info).fetch(:hex_version))
      end

      sig { returns(String) }
      def elixir_version
        T.must(T.must(hex_info).fetch(:elixir_version))
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
      def hex_info
        @hex_info ||= T.let(begin
          version = SharedHelpers.run_shell_command("mix hex.info")
          {
            hex_version: version.match(/Hex: \s*(\d+\.\d+(.\d+)*)/)&.captures&.first,
            elixir_version: version.match(/Elixir: \s*(\d+\.\d+(.\d+)*)/)&.captures&.first
          }
        end, T.nilable(T::Hash[Symbol, T.nilable(String)]))
      end
    end
  end
end

Dependabot::FileParsers.register("hex", Dependabot::Hex::FileParser)

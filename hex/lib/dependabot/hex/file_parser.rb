# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/hex/file_updater/mixfile_sanitizer"
require "dependabot/hex/native_helpers"
require "dependabot/shared_helpers"
require "dependabot/errors"

# For docs, see https://hexdocs.pm/mix/Mix.Tasks.Deps.html
module Dependabot
  module Hex
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"

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

      private

      def dependency_details
        SharedHelpers.in_a_temporary_directory do
          write_sanitized_mixfiles
          write_sanitized_supporting_files
          File.write("mix.lock", lockfile.content) if lockfile
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
          e.message.lines.
          drop_while { |l| !l.start_with?('{"result":') }.
          join

        raise DependencyFileNotEvaluatable, e.message if result_json.empty?

        JSON.parse(result_json).fetch("result")
      end

      def write_sanitized_mixfiles
        mixfiles.each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, sanitize_mixfile(file.content))
        end
      end

      def write_sanitized_supporting_files
        dependency_files.select(&:support_file).each do |file|
          path = file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, sanitize_mixfile(file.content))
        end
      end

      def sanitize_mixfile(content)
        Hex::FileUpdater::MixfileSanitizer.new(
          mixfile_content: content
        ).sanitized_content
      end

      def mix_env
        {
          "MIX_EXS" => File.join(NativeHelpers.hex_helpers_dir, "mix.exs"),
          "MIX_LOCK" => File.join(NativeHelpers.hex_helpers_dir, "mix.lock"),
          "MIX_DEPS" => File.join(NativeHelpers.hex_helpers_dir, "deps"),
          "MIX_QUIET" => "1"
        }
      end

      def elixir_helper_path
        File.join(NativeHelpers.hex_helpers_dir, "lib/run.exs")
      end

      def elixir_helper_parse_deps_path
        File.join(NativeHelpers.hex_helpers_dir, "lib/parse_deps.exs")
      end

      def check_required_files
        raise "No mixfile!" if mixfiles.none?
      end

      def symbolize_keys(hash)
        hash.keys.to_h { |k| [k.to_sym, hash[k]] }
      end

      def mixfiles
        dependency_files.select { |f| f.name.end_with?("mix.exs") }
      end

      def lockfile
        @lockfile ||= get_original_file("mix.lock")
      end
    end
  end
end

Dependabot::FileParsers.register("hex", Dependabot::Hex::FileParser)

# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/helpers"
require "dependabot/mise/version"
require "dependabot/shared_helpers"
require "json"

module Dependabot
  module Mise
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig
      include Dependabot::Mise::Helpers

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        Dependabot::SharedHelpers.in_a_temporary_directory do
          write_manifest_files(dependency_files)

          raw = Dependabot::SharedHelpers.run_shell_command(
            "mise ls --current --local --json",
            stderr_to_stdout: false,
            env: { "MISE_YES" => "1" }
          )

          JSON.parse(raw).filter_map do |tool_name, entries|
            entry = Array(entries).first
            next unless entry

            requested = entry["requested_version"]
            next unless requested
            # Skip fuzzy pins like "latest" or "lts" — they have no specific version
            # to compare against and would break version comparison in the base class.
            next unless Dependabot::Mise::Version.correct?(requested)

            # `version` is what mise resolved (used for version comparison).
            # `requested_version` is what's written in mise.toml (used by the file updater).
            resolved = entry["version"] || requested

            build_dependency(tool_name, resolved, requested)
          end
        end
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn("mise ls failed: #{e.message}")
        []
      rescue JSON::ParserError => e
        Dependabot.logger.warn("mise ls returned invalid JSON: #{e.message}")
        []
      end

      private

      sig do
        params(name: String, version: String, requirement: String)
          .returns(Dependabot::Dependency)
      end
      def build_dependency(name, version, requirement)
        Dependabot::Dependency.new(
          name: name,
          version: version,
          package_manager: "mise",
          requirements: [{
            requirement: requirement,
            file: Dependabot::Mise::FileFetcher::MANIFEST_FILE,
            groups: [],
            source: nil
          }]
        )
      end

      sig { override.void }
      def check_required_files
        return if get_original_file(Dependabot::Mise::FileFetcher::MANIFEST_FILE)

        raise "No #{Dependabot::Mise::FileFetcher::MANIFEST_FILE} file found!"
      end
    end
  end
end

Dependabot::FileParsers.register("mise", Dependabot::Mise::FileParser)

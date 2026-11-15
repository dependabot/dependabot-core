# typed: strong
# frozen_string_literal: true

require "fileutils"

require "dependabot/shared_helpers"

module Dependabot
  module Mise
    module Helpers
      extend T::Sig

      private

      sig { params(manifest_name: String, tool_name: T.nilable(String)).returns(String) }
      def mise_ls(manifest_name, tool_name = nil)
        command = ["mise", "ls", "--current", "--no-global", "--json"]
        command += ["--", tool_name] if tool_name

        Dependabot::SharedHelpers.run_shell_command(
          command,
          stderr_to_stdout: false,
          env: { "MISE_YES" => "1", "MISE_SAFE" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => manifest_name }
        )
      end

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
      def write_manifest_files(dependency_files)
        dependency_files.each do |file|
          FileUtils.mkdir_p(File.dirname(file.name))
          File.write(file.name, file.content)
        end
      end
    end
  end
end

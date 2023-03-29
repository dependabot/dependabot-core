# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/npm_and_yarn/native_helpers"

module Dependabot
  module NpmAndYarn
    class FileParser
      class YarnLock
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        def parse
          SharedHelpers.in_a_temporary_directory do
            File.write("yarn.lock", @dependency_file.content)

            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "yarn:parseLockfile",
              args: [Dir.pwd]
            )
          rescue SharedHelpers::HelperSubprocessFailed
            raise Dependabot::DependencyFileNotParseable, @dependency_file.path
          end
        end
      end
    end
  end
end

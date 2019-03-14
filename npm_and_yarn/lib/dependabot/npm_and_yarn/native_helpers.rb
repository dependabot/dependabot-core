# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module NativeHelpers
      def self.helper_path
        "node #{File.join(native_helpers_root, 'run.js')}"
      end

      def self.native_helpers_root
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "npm_and_yarn") unless helpers_root.nil?

        File.join(__dir__, "../../../../npm_and_yarn/helpers")
      end
    end
  end
end

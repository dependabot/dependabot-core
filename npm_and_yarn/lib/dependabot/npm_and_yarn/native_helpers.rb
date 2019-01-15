# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module NativeHelpers
      def self.npm_helper_path
        File.join(npm_helpers_dir, "bin/run.js")
      end

      def self.npm_helpers_dir
        File.join(native_helpers_root, "npm_and_yarn/helpers/npm")
      end

      def self.yarn_helper_path
        File.join(yarn_helpers_dir, "bin/run.js")
      end

      def self.yarn_helpers_dir
        File.join(native_helpers_root, "npm_and_yarn/helpers/yarn")
      end

      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../..")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end
    end
  end
end

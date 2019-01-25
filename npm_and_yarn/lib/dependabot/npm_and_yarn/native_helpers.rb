# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module NativeHelpers
      def self.npm_helper_path
        File.join(npm_helpers_dir, "bin/run.js")
      end

      def self.yarn_helpers_dir
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        unless helpers_root.nil?
          return File.join(helpers_root, "npm_and_yarn/npm")
        end

        File.join(default_helpers_dir, "npm")
      end


      def self.yarn_helper_path
        File.join(yarn_helpers_dir, "bin/run.js")
      end

      def self.yarn_helpers_dir
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        unless helpers_root.nil?
          return File.join(helpers_root, "npm_and_yarn/yarn")
        end

        File.join(default_helpers_dir, "yarn")
      end

      def self.default_helpers_dir
        File.join(__dir__, "../../../../npm_and_yarn/helpers")
      end
    end
  end
end

# frozen_string_literal: true

module Dependabot
  module GoModules
    module NativeHelpers
      def self.helper_path
        clean_path(File.join(helpers_dir, "bin/helper"))
      end

      def self.helpers_dir
        File.join(native_helpers_root, "go_modules/helpers")
      end

      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../..")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end

# frozen_string_literal: true

module Dependabot
  module Composer
    module NativeHelpers
      def self.composer_helper_path(composer_version: "2")
        File.join(composer_helpers_dir, "v#{composer_version}", "bin/run")
      end

      def self.composer_helpers_dir
        File.join(native_helpers_root, "composer")
      end

      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../..")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end
    end
  end
end

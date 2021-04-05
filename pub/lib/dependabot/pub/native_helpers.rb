# frozen_string_literal: true

module Dependabot
  module Pub
    module NativeHelpers
      def self.helper_path
        "dart --no-sound-null-safety run #{File.join(native_helpers_root, './bin/run.dart')}"
      end

      def self.native_helpers_root
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "pub") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end
    end
  end
end

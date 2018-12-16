# frozen_string_literal: true

module Dependabot
  module Hex
    module NativeHelpers
      def self.hex_helpers_dir
        File.join(native_helpers_root, "hex/helpers")
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

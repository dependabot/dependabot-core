# frozen_string_literal: true

module Dependabot
  module Hex
    module NativeHelpers
      def self.hex_helpers_dir
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "hex") unless helpers_root.nil?

        File.join(__dir__, "../../../../hex/helpers")
      end

      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end

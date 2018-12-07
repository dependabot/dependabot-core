# frozen_string_literal: true

module Dependabot
  module Python
    module NativeHelpers
      def self.python_helper_path
        helpers_dir = File.join(native_helpers_root, "python/helpers")
        Pathname.new(File.join(helpers_dir, "run.py")).cleanpath.to_path
      end

      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../..")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end
    end
  end
end

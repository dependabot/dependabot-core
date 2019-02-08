# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module NativeHelpers
      def self.helper_path
        "node #{File.join(native_helpers_root, 'npm_and_yarn/run.js')}"
      end

      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/install-dir")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end
    end
  end
end

# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Bun
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.helper_path
        "node #{File.join(native_helpers_root, 'run.js')}"
      end

      sig { returns(String) }
      def self.native_helpers_root
        helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        return File.join(helpers_root, "bun") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end
    end
  end
end

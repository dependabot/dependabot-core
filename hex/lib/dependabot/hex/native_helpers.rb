# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Hex
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.hex_helpers_dir
        helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        return File.join(helpers_root, "hex") unless helpers_root.nil?

        File.join(__dir__, "../../../../hex/helpers")
      end

      sig { params(path: String).returns(String) }
      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end

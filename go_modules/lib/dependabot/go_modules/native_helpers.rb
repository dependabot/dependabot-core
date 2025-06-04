# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GoModules
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.helper_path
        clean_path(File.join(native_helpers_root, "go_modules/bin/helper"))
      end

      sig { returns(String) }
      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/install-dir")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      sig { params(path: String).returns(String) }
      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end

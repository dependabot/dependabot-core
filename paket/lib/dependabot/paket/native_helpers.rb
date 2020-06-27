# frozen_string_literal: true

module Dependabot
  module Paket
    module NativeHelpers
      def self.helper_path
        clean_path(File.join(native_helpers_root, "src/bin/netcoreapp3.1/native-paket-helpers.dll"))
      end

      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end

# frozen_string_literal: true

module Dependabot
  module Python
    module NativeHelpers
      def self.python_helper_path
        clean_path(File.join(python_helpers_dir, "run.py"))
      end

      def self.python_requirements_path
        clean_path(File.join(python_helpers_dir, "requirements.txt"))
      end

      def self.python_helpers_dir
        File.join(native_helpers_root, "python")
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

# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "open3"
require "dependabot/errors"

module Dependabot
  module CrystalShards
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.shards_path
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)&.then { |p| File.join(p, "crystal_shards", "shards") } ||
          find_shards_binary
      end

      sig { returns(String) }
      def self.find_shards_binary
        common_paths = [
          "/usr/local/bin/shards",
          "/usr/bin/shards"
        ]

        found = common_paths.find { |p| File.executable?(p) }
        return found if found

        begin
          stdout, status = Open3.capture2("which", "shards")
          path = stdout.strip
          return path if status.success? && !path.empty? && File.executable?(path)
        rescue StandardError
          nil
        end

        raise Dependabot::DependencyFileNotResolvable,
              "Crystal shards binary not found. Please ensure Crystal is installed."
      end
    end
  end
end

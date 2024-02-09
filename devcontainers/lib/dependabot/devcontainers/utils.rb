# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Devcontainers
    module Utils
      extend T::Sig

      sig { params(directory: String).returns(String) }
      def self.expected_config_basename(directory)
        root_directory?(directory) ? ".devcontainer.json" : "devcontainer.json"
      end

      sig { params(directory: String).returns(T::Boolean) }
      def self.root_directory?(directory)
        Pathname.new(directory).cleanpath.to_path == Pathname.new(".").cleanpath.to_path
      end

      sig { params(config_file_name: String).returns(String) }
      def self.expected_lockfile_name(config_file_name)
        if config_file_name.start_with?(".")
          ".devcontainer-lock.json"
        else
          "devcontainer-lock.json"
        end
      end
    end
  end
end

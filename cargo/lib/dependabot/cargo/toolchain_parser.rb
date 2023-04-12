require "toml-rb"

module Dependabot
  module Cargo
    class ToolchainParser
      def initialize(toolchain)
        @toolchain = toolchain
      end

      def sparse_flag
        return @sparse_flag if defined?(@sparse_flag)

        @sparse_flag = needs_sparse_flag ? "-Z sparse-registry" : ""
      end

      private

      attr_reader :toolchain

      def needs_sparse_flag
        return false unless toolchain

        channel = TomlRB.parse(toolchain.content).fetch("toolchain", nil)&.fetch("channel", nil)
        return false unless channel

        date = channel.match(/nightly-(\d{4}-\d{2}-\d{2})/)&.captures&.first
        return false unless date

        Date.parse(date) < Date.parse("2023-01-20")
      end
    end
  end
end

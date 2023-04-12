# frozen_string_literal: true

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

      # We only need to set the -Z sparse-registry flag for nightly and unstable toolchains
      # during which the feature exists and is reading the environment variable CARGO_REGISTRIES_CRATES_IO_PROTOCOL.
      def needs_sparse_flag
        return false unless toolchain

        channel = TomlRB.parse(toolchain.content).fetch("toolchain", nil)&.fetch("channel", nil)
        return false unless channel

        date = channel.match(/nightly-(\d{4}-\d{2}-\d{2})/)&.captures&.first
        return false unless date

        Date.parse(date).between?(Date.parse("2022-07-10"), Date.parse("2023-01-20"))
      end
    end
  end
end

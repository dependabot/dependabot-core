# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_parsers/base"

module Dependabot
  module Cargo
    class FileParser < Dependabot::FileParsers::Base
      class ToolchainChannelParser
        extend T::Sig

        sig { params(toolchain: String).void }
        def initialize(toolchain)
          @toolchain = toolchain
        end

        # Parse Rust toolchain and extract components (channel, date, version)
        #
        # This doesn't support the full range of Rust toolchain formats, but we cover
        # those that Dependabot is likely to encounter.
        #
        # See https://rust-lang.github.io/rustup/concepts/toolchains.html
        sig { returns(T.nilable(T::Hash[Symbol, T.nilable(String)])) }
        def parse
          case toolchain
          # Specific version like 1.72.0 or 1.72
          when /^\d+\.\d+(\.\d+)?$/
            {
              channel: nil,
              date: nil,
              version: toolchain
            }
          # With date: nightly-2025-01-0, beta-2025-01-0, stable-2025-01-0
          when /^(nightly|beta|stable)-(\d{4}-\d{2}-\d{2})$/
            {
              channel: ::Regexp.last_match(1),
              date: ::Regexp.last_match(2),
              version: nil
            }
          # Without date: nightly, beta, stable
          when "nightly", "beta", "stable"
            {
              channel: toolchain,
              date: nil,
              version: nil
            }
          end
        end

        private

        sig { returns(String) }
        attr_reader :toolchain
      end
    end
  end
end

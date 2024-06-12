# typed: strict
# frozen_string_literal: true

require "dependabot/hex/file_updater"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Hex
    class FileUpdater
      class MixfileGitPinUpdater
        extend T::Sig

        sig { params(dependency_name: String, mixfile_content: String, previous_pin: String, updated_pin: String).void }
        def initialize(dependency_name:, mixfile_content:,
                       previous_pin:, updated_pin:)
          @dependency_name = dependency_name
          @mixfile_content = mixfile_content
          @previous_pin    = previous_pin
          @updated_pin     = updated_pin
        end

        sig { returns(String) }
        def updated_content
          updated_content = update_pin(mixfile_content)

          raise "Expected content to change!" if content_should_change? && mixfile_content == updated_content

          updated_content
        end

        private

        sig { returns(String) }
        attr_reader :dependency_name

        sig { returns(String) }
        attr_reader :mixfile_content

        sig { returns(String) }
        attr_reader :previous_pin

        sig { returns(String) }
        attr_reader :updated_pin

        sig { params(content: String).returns(String) }
        def update_pin(content)
          requirement_line_regex =
            /
              \{\s*:#{Regexp.escape(dependency_name)},[^\}]*
              (?:ref|tag):\s+["']#{Regexp.escape(previous_pin)}["']
            /mx

          content.gsub(requirement_line_regex) do |requirement_line|
            requirement_line.gsub(previous_pin, updated_pin)
          end
        end

        sig { returns(T::Boolean) }
        def content_should_change?
          previous_pin == updated_pin
        end
      end
    end
  end
end

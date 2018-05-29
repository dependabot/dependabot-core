# frozen_string_literal: true

require "dependabot/file_updaters/elixir/hex"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex
        class MixfileGitPinUpdater
          def initialize(dependency_name:, mixfile_content:,
                         previous_pin:, updated_pin:)
            @dependency_name = dependency_name
            @mixfile_content = mixfile_content
            @previous_pin    = previous_pin
            @updated_pin     = updated_pin
          end

          def updated_content
            updated_content = update_pin(mixfile_content)

            if content_should_change? && mixfile_content == updated_content
              raise "Expected content to change!"
            end

            updated_content
          end

          private

          attr_reader :dependency_name, :mixfile_content,
                      :previous_pin, :updated_pin

          def update_pin(content)
            requirement_line_regex =
              /
                :#{Regexp.escape(dependency_name)},.*
                (?:ref|tag):\s+["']#{Regexp.escape(previous_pin)}["']
              /x

            content.gsub(requirement_line_regex) do |requirement_line|
              requirement_line.gsub(previous_pin, updated_pin)
            end
          end

          def content_should_change?
            previous_pin == updated_pin
          end
        end
      end
    end
  end
end
